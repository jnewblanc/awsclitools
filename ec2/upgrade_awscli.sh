#!/bin/bash
#
# Script to update awscli on long running ec2 instances
#
# To use:
#   * Stash your packages in a readable s3 bucket
#   * configure this with the necessary versions/paths/etc
#   * deploy to ec2 instance
#   * run script on instance, or deploy a cron
#

s3bucket="public_packages"
awscli_version="1.9.110"

usage() {
  echo "Usage: $0 [options] <version number>"
  echo "Example: "
  echo "    $0 -i[nstall] 1.9.110   : this will try to install awscli bundle version 1.9.110"
  echo "    $0 -v[ersion]           : this will display the current installed awscli bundle version"
  exit 0
}

if [ $# -eq 0 ]; then
  usage
fi

show_version=''
while [ $# -gt 0 ]; do
  if [ "$1" = '-install' -o "$1" = '-i' ]; then
    shift; awscli_version=$1
  elif [ "$1" = '-version' -o "$1" = '-v' ]; then
    shift; show_version='true'
  else
    usage
  fi
  shift
done

awscli_bin_location='/usr/local/aws/bin'
awscli="${awscli_bin_location}/aws"

#
# System command & output example:
# > /usr/local/aws/bin/aws --version
# aws-cli/1.11.154 Python/2.6.6 Linux/2.6.32-504.12.2.el6.x86_64 botocore/1.7.12
#
get_version() {
  installed_awscli=$(${awscli} --version 2>&1)
  installed_awscli_version=$(echo "${installed_awscli}" | awk '{print $1}' | awk -F/ '{print $2}')
  echo $installed_awscli_version
}

installed_version=$(get_version)

if [ "${show_version}" = 'true' ]; then
  echo $installed_version
  exit 0
fi

if [ "${installed_version}" = "${awscli_version}" ]; then
  echo "    AWS CLI is up-to-date (version: ${installed_version})"
  exit 0
fi

CENTOS7_CHECK=$(cat /etc/system-release-cpe | grep 'centos:7')
# Install python-devel rpm (required by PyYAML-3.12) if it has not been
# installed.
rpm -q python-devel
if [ "$?" = "1" ]; then
  echo "    Install python-devel rpm"
  if [ "${CENTOS7_CHECK}" != "" ]; then
    PYTHON_DEVEL_RPM_URL=https://s3-us-west-2.amazonaws.com/${s3bucket}/python-devel-2.7.5-58.el7.x86_64.rpm
  else
    PYTHON_DEVEL_RPM_URL=https://s3-us-west-2.amazonaws.com/${s3bucket}/python-devel-2.6.6-66.el6_8.x86_64.rpm
  fi
  /usr/bin/yum install -y ${PYTHON_DEVEL_RPM_URL}
fi

echo "    Install AWS CLI Version: ${awscli_version}"
if [ ! -f /root/install/awscli/awscli-bundle/packages/awscli-bundle-${awscli_version}.zip ]; then
  if [ -d /root/install/awscli/awscli-bundle ]; then
    mv -f /root/install/awscli/awscli-bundle /root/install/awscli/awscli-bundle-$(date +%Y%m%d_%H%M%S)
  fi
  mkdir -p /root/install/awscli
  /usr/bin/wget --no-verbose -O /root/install/awscli/awscli-bundle-${awscli_version}.zip https://s3-us-west-2.amazonaws.com/${s3bucket}/awscli-bundle-${awscli_version}.zip
  (cd /root/install/awscli ; unzip -o /root/install/awscli/awscli-bundle-${awscli_version}.zip)
  /root/install/awscli/awscli-bundle/install -i /usr/local/aws -b /usr/local/bin/aws
fi
