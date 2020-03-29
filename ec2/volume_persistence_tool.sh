#!/bin/sh
#
# Make a volume persistent or nonpersistent when it's instance terminates
#
#
PRIMARY_AWS_REGION=us-west-2

usage () {
  echo "$0 -mountpoint <mountpoint> <-persist || -terminate>"
  exit 0
}

# Parse command line options
#
while [ $# -gt 0 ]; do
    if [ "$1" = "-debug" -o "$1" = "-d" ]; then
      # the -x option turns on command echoing as the script runs
      set -x
      DEBUG=1
    elif [  "$1" = "-mount" -o "$1" = "-mountpoint" -o "$1" = "-m" -o "$1" = "-mp" ]; then
      shift ; MOUNTNAME=$1
    elif [  "$1" = "-persist" ]; then
      PERSIST_STATE=persist
    elif [  "$1" = "-terminate" ]; then
      PERSIST_STATE=terminate
    fi
  shift
done

if [ "${MOUNTNAME}" = "" -o "${PERSIST_STATE}" = "" ]; then
  usage
fi

export SCRIPTDIR=`cd \`dirname $0\`; pwd`
  . ${SCRIPTDIR}/../lib/aws_lib.sh
SCRIPTNAME=`basename $0`

TIMESTAMP=`date +'%Y-%m-%d %T'`
echo "$TIMESTAMP INFO Running ${SCRIPTNAME}"
HOSTNAME=`/bin/hostname`

# Get the instance ID
instance_id=`wget -q -O- http://169.254.169.254/latest/meta-data/instance-id`
if [ "${instance_id}" = "" ]; then
  echo "${TIMESTAMP} ERROR Could not determine instance ID.  Aborting"
  exit 1
fi 
echo "instance_id=${instance_id}"

# Linux device names are /dev/xvd* while the aws names are /dev/sd*.  For now,
# we assume that there's a direct mapping, but this might not always be true.
# The "sed command at the end, is intended to do this translation.
device_name=`/bin/lsblk --output 'NAME,MOUNTPOINT' --noheadings -l | /bin/grep ${MOUNTNAME} | /bin/awk '{print $1}' | /bin/sed -e 's#^xv#/dev/s#'`
if [ "${device_name}" = "" ]; then
  echo "${TIMESTAMP} ERROR Could not determine device_name.  Aborting"
  /bin/lsblk -l
  exit 1
fi 
echo "device_name=${device_name}"

# Verify that the device name exists, by checking the status
current_terminate_status=`aws ec2 describe-volumes  --filters Name=attachment.instance-id,Values=${instance_id} Name=attachment.device,Values=/dev/sdi | /bin/grep DeleteOnTermination | /bin/awk '{print $2}'`
echo "initial_terminate_status=${current_terminate_status}"
if [ "${current_terminate_status}" = "" ]; then
  echo "${TIMESTAMP} ERROR Could not verify the device_name ${device_name}.  Aborting"
  /bin/lsblk -l
  exit 1
fi

TIMESTAMP=`date +'%Y-%m-%d %T'`
if [ "${PERSIST_STATE}" = "terminate" ]; then
  setVolToTerminate ${instance_id} ${device_name}
elif [ "${PERSIST_STATE}" = "persist" ]; then
  setVolToPersist ${instance_id} ${device_name}
else
  echo "${TIMESTAMP} WARN No change made"
fi

TIMESTAMP=`date +'%Y-%m-%d %T'`
echo "${TIMESTAMP} INFO The change isn't instantanious, but you can use the following command to check the status"
echo "  aws ec2 describe-volumes --filters Name=attachment.instance-id,Values=${instance_id} Name=attachment.device,Values=${device_name}"

echo "$TIMESTAMP INFO Done with ${SCRIPTNAME}"
exit 0

