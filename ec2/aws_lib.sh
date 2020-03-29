#!/bin/sh
#
# Set of functions that make it easier to run aws commands

AWS="/usr/local/bin/aws --profile snapshot"

################
getRaidDevices() {
  local MOUNTNAME=$1

   TIMESTAMP=`date +'%Y-%m-%d %T'`

  if [ "${MOUNTNAME}" = "" ]; then
    # Default to getting all raid devices
    MOUNTNAME="raid"
  fi

  # Get device name of raid volume
  if [ "${DEBUG}" = "1" ]; then
    echo "cat /proc/mounts | grep \"${MOUNTNAME}\" | cut -f 1 -d' ' | cut -f 3 -d'/'"
  fi
  RAID_DEVICES=`cat /proc/mounts | grep "${MOUNTNAME}" | cut -f 1 -d' ' | cut -f 3 -d'/'`
  if [ "${RAID_DEVICES}" = "" ]; then
    echo "${TIMESTAMP} ERROR Could not find any devices that match \"${MOUNTNAME}\""
    return 1
  fi
  if [ "${DEBUG}" = "1" ]; then
    echo "${TIMESTAMP} INFO Raid Devices: ${RAID_DEVICES}"
  fi

  # RAID_DEVICES is the return value
  return 0
}

#####################
getVolumesForDevice() {
  local DEVICENAME=$1

  TIMESTAMP=`date +'%Y-%m-%d %T'`
  if [ "${DEBUG}" = "1" ]; then
    echo "cat /proc/mdstat | grep ${DEVICENAME} | sed -e 's/.\*raid0 //' | sed -e 's/\[[0-9]\]//g'"
  fi
  FOUND_VOLS=`cat /proc/mdstat | grep ${DEVICENAME} | sed -e 's/.*raid0 //' | sed -e 's/\[[0-9]\]//g'`
  if [ "${FOUND_VOLS}" = "" ]; then
    echo "${TIMESTAMP} ERROR Could not find any volumes for \"${DEVICENAME}\""
    return 1
  fi
  if [ "${DEBUG}" = "1" ]; then
    echo "${TIMESTAMP} INFO Volumes for devices \"${DEVICENAME}\": ${FOUND_VOLS}"
  fi

  # FOUND_VOLS is the return value
  return 0
}

#################
getAWSVolumesID() {
  local INSTANCE=$1
  local VOLNAME=$2

  TIMESTAMP=`date +'%Y-%m-%d %T'`
  if [ "${DEBUG}" = "1" ]; then
    echo "$AWS ec2 describe-volumes --output text --filter \"Name=attachment.instance-id,Values=${INSTANCE}\" \"Name=attachment.device,Values=${VOLNAME}\" --output text | grep VOLUMES | cut -f 7 -s"
  fi
  VOL_ID=`$AWS ec2 describe-volumes --output text --filter "Name=attachment.instance-id,Values=${INSTANCE}" "Name=attachment.device,Values=${VOLNAME}" --output text | grep VOLUMES | cut -f 7 -s`
  if [ "${VOL_ID}" = "" ]; then
    echo "${TIMESTAMP} ERROR Could not find any volumes for \"${VOL_ID}\""
    return 1
  fi
  if [ "${DEBUG}" = "1" ]; then
    echo "${TIMESTAMP} INFO VolumeID for volume \"${VOLNAME}\": ${VOL_ID}"
  fi

  # VOL_ID is the return value
  return 0
}

################
createSnapshot() {
  local instance_id=$1
  local volume_id=$2
  local hostname=$3

  if [ "${hostname}" = "" ]; then
    hostname=`/bin/hostname`
  fi
  TIMESTAMP=`date +'%Y-%m-%d %T'`
  DESC_TIMESTAMP=`date +'%Y-%m-%d.%H:%M'`
  description="backup_${hostname}_${instance_id}_${volume_id}_${DESC_TIMESTAMP}"
  echo "${TIMESTAMP} INFO Creating Snapshot for volume $volume_id with description: $description"
  if [ "${DEBUG}" = "1" ]; then
    echo "$AWS ec2 create-snapshot --description $description --volume-id \"$volume_id\""
  fi
  SNAPSHOT_OUT=`$AWS ec2 create-snapshot --description $description --volume-id "$volume_id"`
  local STATUS=$?
  if [ "${STATUS}" = "0" ]; then
    SNAPSHOT_ID=`echo ${SNAPSHOT_OUT} | sed -e 's/.*SnapshotId": "\([^"]*\)".*$/\1/g' | grep -e "^snap"`
  fi

  # SNAPSHOT_ID is the return value
  return $STATUS
}

###########
tagSnapshot() {
  local snapshot_id=$1
  local tag_name=$2
  local tag_value=$3

  $AWS ec2 create-tags --resources "${snapshot_id}" --tags "Key=${tag_name},Value=${tag_value}" > /dev/null
  if [ "$?" != "0" ]; then
    TIMESTAMP=`date +'%Y-%m-%d %T'`
    echo "${TIMESTAMP} ERROR Could not tag snapshot ${snapshot_id}" 
  fi
}

###############
rollSnapshots() {
  local instance_id=$1
  local volume_id=$2
  local hostname=$3

  local num_to_keep=3

  if [ "${hostname}" = "" ]; then
    hostname=`/bin/hostname`
  fi
  TIMESTAMP=`date +'%Y-%m-%d %T'`

  echo "${TIMESTAMP} INFO Purging outdated snapshots for ${volume_id}"
  # Get all snapshot info
  echo "num_to_keep = ${num_to_keep}"
  # Since we use tail, we need to increment this by one to get the right amount
  num_to_keep=`expr $num_to_keep + 1`
  if [ "${DEBUG}" = "1" ]; then
    echo "$AWS ec2 describe-snapshots --filters \"Name=volume-id,Values=${volume_id}\" \"Name=tag-key,Values=AutoPurge\" \"Name=tag-value,Values=true\" --output text | grep SNAPSHOTS | awk '{print \$2}' | sort --general-numeric-sort | tail -n +${num_to_keep}"
  fi
  MATCHING_SNAPSHOT_COUNT=`$AWS ec2 describe-snapshots --filters "Name=volume-id,Values=${volume_id}" "Name=tag-key,Values=AutoPurge" "Name=tag-value,Values=true" --output text | grep SNAPSHOTS | wc -l`
  sleep 1
  # The last grep is just for extra precaution
  SNAPSHOTS_TO_PURGE=`$AWS ec2 describe-snapshots --filters "Name=volume-id,Values=${volume_id}" "Name=tag-key,Values=AutoPurge" "Name=tag-value,Values=true" --output text | grep SNAPSHOTS | awk '{print $2}' | sort --general-numeric-sort --reverse | tail -n +${num_to_keep} | grep "backup_${hostname}_${instance_id}_${volume_id}"`
  sleep 1

  echo "MATCHING_SNAPSHOT_COUNT = ${MATCHING_SNAPSHOT_COUNT}"
  if [ "${SNAPSHOTS_TO_PURGE}" = "" ]; then
    echo "$TIMESTAMP WARN No snapshots matching volume_id ${volume_id} and instance_id ${instance_id} need to be purged"
    return 0
  fi

  for one_snap in ${SNAPSHOTS_TO_PURGE} ; do
    local snapshot_ids=`$AWS ec2 describe-snapshots --filters "Name=description,Values=${one_snap}" --query 'Snapshots[*].SnapshotId' --output text`
    sleep 1
    # There is typically ony one, but we handle multiple.  This can happen
    # during testing if two snapshots are created during the same minute
    for snapshot_id in ${snapshot_ids} ; do
      TIMESTAMP=`date +'%Y-%m-%d %T'`
      GREP_CHECK=`echo "${snapshot_id}" | grep snap-`
      if [ "${GREP_CHECK}" = "" ]; then
        echo "$TIMESTAMP WARN \"${snapshot_id}\" is not a valid snapshot ID.  Skipping"
      else
        echo "${TIMESTAMP} INFO Purging obsolete snapshot ${snapshot_id} ($one_snap)"
        if [ "${DEBUG}" = "1" ]; then
          echo "$AWS ec2 delete-snapshot --snapshot-id ${snapshot_id}"
        fi
        $AWS ec2 delete-snapshot --snapshot-id ${snapshot_id} > /dev/null
        sleep 1
        if [ "$?" != "0" ]; then
          echo "${TIMESTAMP} ERROR Could not delete snapshot ${snapshot_id}" 
        fi
      fi
    done
  done
}

#########################
getVolIdsForBackUpVolumes() {
  local INSTANCE=$1
  echo "$AWS ec2 describe-volumes --filter \"Name=attachment.instance-id,Values=${INSTANCE}\" \"Name=tag-key,Values=backup\" \"Name=tag-value,Values=true\" --query 'Volumes[*].VolumeId' --output text"
  VOL_LIST=`$AWS ec2 describe-volumes --filter "Name=attachment.instance-id,Values=${INSTANCE}" "Name=tag-key,Values=backup" "Name=tag-value,Values=true" --query 'Volumes[*].VolumeId' --output text`
}

#################
setVolToTerminate() {
  local INSTANCE=$1
  local DEVICE=$2
 # http://docs.aws.amazon.com/AWSEC2/latest/UserGuide/terminating-instances.html#preserving-volumes-on-termination
  /usr/local/bin/aws --profile autoprov ec2 modify-instance-attribute --instance-id ${INSTANCE} --block-device-mappings "[{\"DeviceName\":\"${DEVICE}\",\"Ebs\":{\"DeleteOnTermination\":true}}]"
}

###############
setVolToPersist() {
  local INSTANCE=$1
  local DEVICE=$2
  /usr/local/bin/aws --profile autoprov ec2 modify-instance-attribute --instance-id ${INSTANCE} --block-device-mappings "[{\"DeviceName\":\"${DEVICE}\",\"Ebs\":{\"DeleteOnTermination\":false}}]"
}

#################
getAWSInstanceHostnameForTag() {
  local TAGNAME=$1
  local TAGVALUE=$2

  TIMESTAMP=`date +'%Y-%m-%d %T'`
  if [ "${DEBUG}" = "1" ]; then
    echo "$AWS ec2 describe-instances --output text --filter \"Name=tag-key,Values=${TAGNAME}\" \"Name=tag-value,Values=${TAGVALUE}\" \"Name=instance-state-name,Values=running\" --output text | grep Name"
  fi
  HOSTNAME_LIST=`$AWS ec2 describe-instances --output text --filter "Name=tag-key,Values=${TAGNAME}" "Name=tag-value,Values=${TAGVALUE}" "Name=instance-state-name,Values=running" --output text 2>&1 | /bin/grep Name | /bin/awk '{print $3}'`
  if [ "${HOSTNAME_LIST}" = "" ]; then
    echo "${TIMESTAMP} ERROR Could not find any instances for \"${TAGNAME}=${TAGVALUE}\""
    return 1
  fi
  if [ "${DEBUG}" = "1" ]; then
    echo "${TIMESTAMP} INFO Instances with tag ${TAGNAME}=${TAGVALUE}"
  fi

  # HOSTNAME_LIST is the return value
  return 0
}

