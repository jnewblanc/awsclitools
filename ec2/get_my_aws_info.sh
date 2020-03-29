#!/bin/sh
#
# Gets a given tag for this host

dataname=$1

if [ "${dataname}" = "" ]; then
  echo "Usage: $0 <tagName> | <otherName>"
  echo "  Common Tags"
  echo "    Name"
  echo "    Role"
  echo "    AMI"
  echo "    aws:cloudformation:stack-name"
  echo "  Other Info"
  echo "    InstanceId"
  echo "    InstanceType"
  echo "    SecurityGroup"
  echo "    AvailibilityZone"
  echo "    AttachedVolumes"
  echo "    UntaggedAttachedVolumes"
  exit 0
fi

function run_cmd {
  cmd=$1
#  echo $cmd
  output=`$cmd 2>&1`
}

# If it's a known meta-data element, set the metadata var
if [ "${dataname}" = "InstanceId" ]; then
  metadata="instance-id"
elif [ "${dataname}" = "InstanceType" ]; then
  metadata="instance-type"
elif [ "${dataname}" = "SecurityGroup" ]; then
  metadata="security-groups"
elif [ "${dataname}" = "AvailibilityZone" ]; then
  metadata="/placement/availability-zone"
fi

if [ "${metadata}" != "" ]; then
  # If it's a known metadata element, retrieve it
  run_cmd "/usr/bin/curl -s http://169.254.169.254/latest/meta-data/${metadata}"
  echo "${output}"
else
  # Get the instance Id
  run_cmd "/usr/bin/curl -s http://169.254.169.254/latest/meta-data/instance-id"
  instance_id=$output

  ##############
  if [ "${dataname}" = "AttachedVolumes" ]; then
    run_cmd "/usr/local/bin/aws ec2 describe-volumes --filters "Name=attachment.instance-id,Values=${instance_id}" --output text"
    volume_info=$output

    # Display the info
    echo "${volume_info}"
  ##############
  elif [ "${dataname}" = "UntaggedAttachedVolumes" ]; then
    # Bypass run_cmd due to compilcations with pipes, quotes, ticks, asteriks,
    # and dollar signs.  I challenge you to get it to work with run_cmd.
    volume_info=`/usr/local/bin/aws ec2 describe-volumes --filters "Name=attachment.instance-id,Values=${instance_id}" --query "Volumes[*].{VolumeId:VolumeId,Tags:Tags}" --output text | grep None | awk '{print \$2}'`

    # Display the info
    echo "${volume_info}"
  ##############
  else
    # At this point, assume dataname is a tag that we need to retrieve
  
    if [ "${dataname}" = "InstanceId" ]; then
      # This isn't really a tag, but it's useful, so we'll make this exception
      echo "${instance_id}"
      exit 0
    fi
  
    # Get the tag
    run_cmd "/usr/local/bin/aws ec2 describe-tags --filters Name=resource-id,Values=${instance_id} Name=key,Values=${dataname} --query Tags[*].Value --output text"
    instance_tag_value=$output
    
    # We've seen cases, where AWS returns an error message instead of the
    # tags, so we try to catch this.  Returning nothing is better than returning
    # the wrong tags
    greperrormsg=`echo ${instance_tag_value} | grep "RequestLimitExceeded"`
    if [ "${greperrormsg}" != "" ]; then
      instance_tag_value=""
    fi
    greperrormsg=`echo ${instance_tag_value} | grep "Unable to locate credentials"`
    if [ "${greperrormsg}" != "" ]; then
      instance_tag_value=""
    fi

    if [[ instance_tag_value =~ "client error" ]]; then
      instance_tag_value=""
    fi
    # Display the tag
    echo "${instance_tag_value}"
  fi
fi

