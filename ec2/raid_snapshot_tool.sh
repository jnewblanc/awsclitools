#!/bin/sh
#
# Tool to create and manage AWS snapshots
#
PRIMARY_AWS_REGION=us-west-2

usage() {
  echo "$0 -mountpoint </mnt/name> [-debug]"
  exit 0
}

#
# Parse command line options
#
while [ $# -gt 0 ]; do
    if [ "$1" = "-debug" -o "$1" = "-d" ]; then
      # the -x option turns on command echoing as the script runs
#      set -x
      DEBUG=1
    elif [  "$1" = "-mount" -o "$1" = "-mountpoint" -o "$1" = "-m" -o "$1" = "-mp" ]; then
      shift ; MOUNTNAME=$1
    fi
  shift
done

if [ "${MOUNTNAME}" = "" ]; then
  usage
fi
 
export SCRIPTDIR=`cd \`dirname $0\`; pwd`
  . ${SCRIPTDIR}/../lib/aws_lib.sh
SCRIPTNAME=`basename $0`

TIMESTAMP=`date +'%Y-%m-%d %T'`
echo "$TIMESTAMP INFO Running ${SCRIPTNAME}"
HOSTNAME=`/bin/hostname`

# Get RAID info - Set $RAID_DEVICES
getRaidDevices ${MOUNTNAME}
if [ "$?" != "0" ]; then
  exit 1
fi

# Get individual volumes for the raid devices
for one_raid in ${RAID_DEVICES} ; do
  # Set $FOUND_VOLS
  getVolumesForDevice ${one_raid}
  if [ "$?" != "0" ]; then
    exit 1
  fi
  ALL_VOLS=`echo "${ALL_VOLS} ${FOUND_VOLS}" | sed -e 's/^ //g'`
done

# Get the instance ID
instance_id=`wget -q -O- http://169.254.169.254/latest/meta-data/instance-id`
echo "instance_id=${instance_id}"

# Roll existing snapshots
for one_volname in ${ALL_VOLS} ; do
  # Get the AWS volumeID for a local volume - Sets $VOL_ID
  getAWSVolumesID "${instance_id}" "/dev/${one_volname}"
  if [ "$?" != "0" ]; then
    exit 1
  fi
  rollSnapshots "$instance_id" "${VOL_ID}"
done

START_LOCK_TIMESTAMP=$(date +%s.%N)
# Lock all the volumes
# Not sure if we need to lock the mount point or the volumes - do both for now
TIMESTAMP=`date +'%Y-%m-%d %T'`
echo "${TIMESTAMP} INFO Freezing \"${MOUNTNAME}\""
/sbin/fsfreeze --freeze ${MOUNTNAME}

# Take a snapshot of all volumes
for one_volname in ${ALL_VOLS} ; do
  # Get the AWS volumeID for a local volume - Sets $VOL_ID
  getAWSVolumesID "${instance_id}" "/dev/${one_volname}"
  if [ "$?" != "0" ]; then
    exit 1
  fi
  createSnapshot "$instance_id" "${VOL_ID}"
  echo "SNAPSHOT_ID=${SNAPSHOT_ID}"
  if [ "${SNAPSHOT_ID}" != "" ]; then
    tagSnapshot "${SNAPSHOT_ID}" Name "${HOSTNAME}_${one_volname}"
    tagSnapshot "${SNAPSHOT_ID}" CreatedBy "${SCRIPTNAME}_on_${HOSTNAME}"
    tagSnapshot "${SNAPSHOT_ID}" Purpose "AutoBackup"
    tagSnapshot "${SNAPSHOT_ID}" AutoPurge "true"
    tagSnapshot "${SNAPSHOT_ID}" SrcInstance "${instance_id}"
    tagSnapshot "${SNAPSHOT_ID}" SrcVolumeName "${one_volname}"
    tagSnapshot "${SNAPSHOT_ID}" SrcVolumeId "${VOL_ID}"
    tagSnapshot "${SNAPSHOT_ID}" SrcRegion "${PRIMARY_AWS_REGION}"
  fi
done

# UnLock all the volumes
TIMESTAMP=`date +'%Y-%m-%d %T'`
echo "${TIMESTAMP} INFO Thawing \"${MOUNTNAME}\""
/sbin/fsfreeze --unfreeze "${MOUNTNAME}"
END_LOCK_TIMESTAMP=$(date +%s.%N)

TIME_LOCKED=$(echo "${END_LOCK_TIMESTAMP} - ${START_LOCK_TIMESTAMP}" | bc)

TIMESTAMP=`date +'%Y-%m-%d %T'`
echo "$TIMESTAMP INFO Time locked = ${TIME_LOCKED} seconds"
echo "$TIMESTAMP INFO Done with ${SCRIPTNAME}"
exit 0

