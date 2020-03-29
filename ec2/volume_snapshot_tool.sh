#!/bin/sh
#
# Tool to create and manage AWS snapshots based on tagged volumes
#
# To setup (via deployment automation):
#    * Ensure that aws creds are deployed
#    * Ensure that aws_lib.sh is deployed
#    * Deploy this script to your ec2 instance - alter paths, per your needs
#    * Deploy corresponding cron job to run this nightly
#
# To use:
#    * tag your volume(s) with backup=true
#

PRIMARY_AWS_REGION=us-west-2

usage() {
  echo "$0 [options]"
  echo "  Options:"
  echo "    -hostname <fqdn_internal_hostname> - Alternate Server to back up"
  echo "    -instanceid <aws_instance_id>      - Alternate Instance to back up"
  echo "    -debug                             - turn on debug output"
  exit 0
}

# Parse command line options
#
while [ $# -gt 0 ]; do
    if [ "$1" = "-debug" -o "$1" = "-d" ]; then
      # the -x option turns on command echoing as the script runs
      set -x
    elif [  "$1" = "-hostname" -o "$1" = "-hn" ]; then
      shift ; ALT_HOSTNAME=$1
    elif [  "$1" = "-instanceid" -o "$1" = "-ii" ]; then
      shift ; ALT_INSTANCE_ID=$1
    fi
  shift
done

export SCRIPTDIR=`cd \`dirname $0\`; pwd`
  . ${SCRIPTDIR}/../lib/aws_lib.sh
SCRIPTNAME=`basename $0`

TIMESTAMP=`date +'%Y-%m-%d %T'`
echo "$TIMESTAMP INFO Running ${SCRIPTNAME}"

# Get the hostname
HOSTNAME=`/bin/hostname`
BACKUP_SERVER=${HOSTNAME}
if [ "${ALT_HOSTNAME}" != "" -a "${ALT_HOSTNAME}" != "${HOSTNAME}" ]; then
  if [ "${ALT_INSTANCE_ID}" = "" ]; then
    echo "ERROR: You must supply an instance id if you supply a hostname"
    usage
  fi
  HOSTNAME="${ALT_HOSTNAME}"
fi

# Get the instance ID
instance_id=`wget -q -O- http://169.254.169.254/latest/meta-data/instance-id`
if [ "${ALT_INSTANCE_ID}" != "" -a "${ALT_INSTANCE_ID}" != "${instance_id}" ]; then
  if [ "${ALT_HOSTNAME}" = "" ]; then
    echo "ERROR: You must supply a hostname if you supply an instance id"
    usage
  fi
  instance_id="${ALT_INSTANCE_ID}"
fi

if [ "${instance_id}" = "" ]; then
  echo "${TIMESTAMP} ERROR Could not determine instance ID.  Aborting"
  exit 1
fi
echo "instance_id=${instance_id}"

# Get volumes that are tagged as backup=true (set VOL_LIST)
getVolIdsForBackUpVolumes "${instance_id}"
if [ "${VOL_LIST}" = "" ]; then
  echo "${TIMESTAMP} INFO No volumes found with tag backup=true"
  exit 0
fi

echo "VOL_LIST = ${VOL_LIST}"

# Loop through the volume list
for one_volname in ${VOL_LIST} ; do
  GREP_CHECK=`echo "${one_volname}" | grep vol-`
  if [ "${GREP_CHECK}" = "" ]; then
    echo "${TIMESTAMP} WARN \"${one_volname}\" is an invalid volume name.  Skipping"
  else
    echo "Backing up volume ${one_volname}"
    # Roll existing snapshots
    rollSnapshots "${instance_id}" "${one_volname}" "${HOSTNAME}"

    # Take a new snapshot
    createSnapshot "$instance_id" "${one_volname}" "${HOSTNAME}"
    echo "SNAPSHOT_ID=${SNAPSHOT_ID}"
    if [ "${SNAPSHOT_ID}" != "" ]; then
      tagSnapshot "${SNAPSHOT_ID}" Name "${HOSTNAME}_${one_volname}"
      tagSnapshot "${SNAPSHOT_ID}" CreatedBy "${SCRIPTNAME}_on_${BACKUP_SERVER}"
      tagSnapshot "${SNAPSHOT_ID}" Purpose "AutoBackup"
      tagSnapshot "${SNAPSHOT_ID}" AutoPurge "true"
      tagSnapshot "${SNAPSHOT_ID}" SrcInstance "${instance_id}"
      tagSnapshot "${SNAPSHOT_ID}" SrcVolumeId "${one_volname}"
      tagSnapshot "${SNAPSHOT_ID}" SrcRegion "${PRIMARY_AWS_REGION}"
      # Special tag for buildmaster hosts
      BUILDMASTER_GREP=`echo ${HOSTNAME} | /bin/grep buildmaster`
      if [ "${BUILDMASTER_GREP}" != "" ]; then
        HOSTNAME_SHORT=`echo ${HOSTNAME} | /bin/sed -e 's/\..*//g'`
        tagSnapshot "${SNAPSHOT_ID}" jenkinsmaster "${HOSTNAME_SHORT}"
      fi
    fi
  fi
done

TIMESTAMP=`date +'%Y-%m-%d %T'`
echo "$TIMESTAMP INFO Done with ${SCRIPTNAME}"
exit 0

