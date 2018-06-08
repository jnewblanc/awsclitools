#!/usr/local/bin/python2.7
# 
# Deletes a single Route53 DNS record if the corresponding server doesn't exist
#
# Run with no args to get the usage

# Default hostedZone if no option is specified on the command line
defaultHostedZoneDns='internal.example.com'
defaultUseColor=False

import argparse
import pprint
import boto3
import datetime
import sys
import re

# Handle command line args and usage
scriptname=str(sys.argv[0])
parser = argparse.ArgumentParser(description='Delete Unused Route53 Records')
parser.add_argument('hostname', metavar='hostname', type=str,
  help='Short name of the host/server')
parser.add_argument('--hostedZone', metavar='hostedzone', type=str,
  default=defaultHostedZoneDns,
  help='The route53 hosted zone, which is the domain name')
parser.add_argument('--verbose', action='store_true', default=False,
  help='turn on verbose output')
parser.add_argument('--debug', action='store_true', default=False,
  help='turn on debug output')
parser.add_argument('--color', action='store_true', default=defaultUseColor,
  help='turn on colorized output')
args = parser.parse_args()

# massage the user args
hostedZoneDns=str(args.hostedZone).strip()
shorthostname=str(args.hostname).replace('.'+hostedZoneDns,'').strip()
fqdn=shorthostname + '.' + hostedZoneDns + '.'
verbose=args.verbose
debug=args.debug
usecolor=args.color

if verbose:
  print "hostedZoneDns = "+hostedZoneDns
  print "shorthostname = "+shorthostname
  print "fqdn = "+fqdn

# Create the route53 client handle
r53client = boto3.client('route53')

# Create a pprint handle so we can dump objects - useful for debugging
pp = pprint.PrettyPrinter(indent=4)


######################
def get_hosted_zone_id(zonename):
  zoneId=''

  response = r53client.list_hosted_zones()
  if debug:
    pp.pprint(response)

  for z in response['HostedZones']:
      if verbose:
        print "name = " + z['Name']
      if str(z['Name']).startswith(zonename):
        zoneId=z['Id']

  return zoneId

###################
def getIpFromRecord(dnsname,zoneId):
  response = r53client.list_resource_record_sets(
    HostedZoneId=zoneId,
    StartRecordType='A',
    StartRecordName=dnsname,
    MaxItems='1'
  )
  if debug:
    pp.pprint(response)

  for r in response['ResourceRecordSets']:
    if r['Name'] == dnsname:
      for s in r['ResourceRecords']:
        return s['Value']
    else:
      return 0

################
def deleteRecord(dnsname,recordType,ip,zoneId):
  response = r53client.change_resource_record_sets(
    HostedZoneId=zoneId,
    ChangeBatch={
      'Changes': [
        {
          'Action': 'DELETE',
          'ResourceRecordSet': {
            'Name': dnsname,
            'Type': recordType,
            'TTL': 300,
            'ResourceRecords': [
              {
                'Value': ip
              }
            ]
          }
        }
      ]
    }
  )
  if debug:
    pp.pprint(response)

#########################
def get_ec2_instance_data(tagkey, tagvalue):
  ec2client = boto3.client('ec2')

  response = ec2client.describe_instances(
    Filters=[
      {
        'Name': 'tag:'+tagkey,
        'Values': [tagvalue]
      }
    ]
  )
  return response


#######
def log(msg):
  ts = datetime.datetime.now().strftime("%D %H:%M:%S")

  # Colors for fancy output
  class bcolors:
      GREEN = '\033[92m'
      WARN  = '\033[93m'
      ERR   = '\033[91m'
      ENDC  = '\033[0m'

  if usecolor:
    if msg.find('ERROR'):
      print bcolors.ERR+ts,msg+bcolors.ENDC
    elif msg.find('WARN'):
      print bcolors.WARN+ts,msg+bcolors.ENDC
    elif msg.find('SUCCESS'):
      print bcolors.GREEN+ts,msg+bcolors.ENDC
    else:
      print ts,msg
  else:
    print ts,msg
  

#-------------------------

# Safety Check - Abort if ec2 instance exists
instanceId=""
instance_data = get_ec2_instance_data("Name",shorthostname)
for r in instance_data['Reservations']:
  for i in r['Instances']:
    instanceId=i['InstanceId']
if instanceId != "":
  log("WARN: Instance " + shorthostname + " (" + instanceId + ") exists.  Aborting")
  exit(0)


hostedzoneId=get_hosted_zone_id(hostedZoneDns).replace('/hostedzone/','')
if verbose:
  print "hostedzoneId = " + hostedzoneId

ip=getIpFromRecord(fqdn,hostedzoneId)
if ip:
  log("INFO: Deleting DNS Record \"" + fqdn + "\" (" + ip + ")")
  deleteRecord(fqdn,'A',ip,hostedzoneId)
  if getIpFromRecord(fqdn,hostedzoneId):
    log("ERROR: DNS Record \"" + fqdn + "\" still exists")
  else:
    log("SUCCESS: DNS Record \"" + fqdn + "\" has been deleted")
else:
  log("WARN: DNS Record \"" + fqdn + "\" doesn't exist in ZoneId " + hostedzoneId)
