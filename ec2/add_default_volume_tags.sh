#!/bin/sh
#
# Get the list of untagged volumes for this instance and then slap some default
# tags on them.

scriptdir=`(cd $(dirname $0); pwd)`

if [ ! -x "${scriptdir}/get_my_aws_info.sh" ]; then
  echo "Can not find ${scriptdir}/get_my_aws_info.sh.  Aborting"
  exit 0
fi

role=`${scriptdir}/get_my_aws_info.sh Role`
if [ "${role}" = "" ]; then
  echo "Could not determine role for this instance.  Aborting"
  exit 0
fi

untaggedVols=`/opt/serviceNow/chefInstalled/bin/get_my_aws_info.sh UntaggedAttachedVolumes`
if [ "${untaggedVols}" = "" ]; then
  echo "Did not detect any untagged volumes for this instance.  Aborting"
  exit 0
fi

for vol in ${untaggedVols} ; do
  nametag="${role}.$$"
  echo "Tagging ${vol} with Name ${nametag}"
  /usr/local/bin/aws ec2 create-tags --profile autoprov --resources ${vol} --tags "Key=Name,Value=${nametag} Key=Role,Value=${role}"
done
