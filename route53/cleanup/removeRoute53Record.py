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
parser.add_argument('--dryrun', action='store_true', default=False,
  help='Run through all the checks, but dont actually delete anything')
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
dryrun=args.dryrun
global verbose; verbose=args.verbose
global debug; debug=args.debug
global usecolor; usecolor=args.color

# Create the route53 client handle
r53client = boto3.client('route53')

# Create a pprint handle so we can dump objects - useful for debugging
pp = pprint.PrettyPrinter(indent=4)


###################### Get hosted zone ID from the hosted zone DNS name
def get_hosted_zone_id(zonename):
  if verbose:
    log ("VERBOSE Retrieving hostedZone for " + zonename)
  zoneId=''

  response = r53client.list_hosted_zones()
  debug_dump(response)

  for z in response['HostedZones']:
      if verbose:
        log("VERBOSE Zonename = " + z['Name'])
      if str(z['Name']).startswith(zonename):
        zoneId=z['Id']

  return zoneId

################### - Get IP address from route53 record
def getIpFromRecord(dnsname,zoneId):
  if verbose:
    log ("VERBOSE Retrieving IP from DNS record " + dnsname + " in zone " + zoneId)
  response = r53client.list_resource_record_sets(
    HostedZoneId=zoneId,
    StartRecordType='A',
    StartRecordName=dnsname,
    MaxItems='1'
  )
  debug_dump(response)

  for r in response['ResourceRecordSets']:
    if r['Name'] == dnsname:
      for s in r['ResourceRecords']:
        return s['Value']
    else:
      return False

################ Delete route53 record
def deleteRecord(dnsname,recordType,ip,zoneId):
  if verbose:
    log ("VERBOSE deleting record " + dnsname)
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
  debug_dump(response)

######################### Get ec2 instance data based on a tag keypair
def get_ec2_instance_data(tagkey, tagvalue):
  if verbose:
    log ("VERBOSE Retrieving data for ec2 instance " + tagkey + ' = ' + tagvalue)
  ec2client = boto3.client('ec2')

  response = ec2client.describe_instances(
    Filters=[
      {
        'Name': 'tag:'+tagkey,
        'Values': [tagvalue]
      }
    ]
  )
  debug_dump(response)
  return response


####### Log output with timestamp and optional colorization
def log(msg):
  ts = datetime.datetime.now().strftime("%D %H:%M:%S")

  # Colors for fancy output
  class bcolors:
      GREEN = '\033[92m'
      WARN  = '\033[93m'
      ERR   = '\033[91m'
      ENDC  = '\033[0m'

  if usecolor:
    if msg.count('ERROR'):
      print bcolors.ERR+ts,msg+bcolors.ENDC
    elif msg.count('WARN'):
      print bcolors.WARN+ts,msg+bcolors.ENDC
    elif msg.count('SUCCESS'):
      print bcolors.GREEN+ts,msg+bcolors.ENDC
    else:
      print ts,msg
  else:
    print ts,msg
  
############## Display object if debug mode is on 
def debug_dump(obj):
  if debug:
    pp.pprint(obj)

#-------------------------

if verbose:
  log ("VERBOSE hostedZoneDns = "+hostedZoneDns)
  log ("VERBOSE shorthostname = "+shorthostname)
  log ("VERBOSE fqdn = "+fqdn)

# Safety Check - Abort if ec2 instance exists
instanceId=""
instanceState=""
instance_data = get_ec2_instance_data("Name",shorthostname)
for r in instance_data['Reservations']:
  for i in r['Instances']:
    instanceId=i['InstanceId']
    if verbose:
      log("VERBOSE instanceId = " + instanceId)
      instanceState=i['State']['Name']
    if verbose:
      log("VERBOSE instanceState = " + instanceState)

if (instanceId != "") and (instanceState != 'terminated'):
  log("WARN Instance " + shorthostname + " (" + instanceId + ") exists.  Aborting")
  exit(0)

hostedzoneId=get_hosted_zone_id(hostedZoneDns).replace('/hostedzone/','')
if verbose:
  log("VERBOSE hostedzoneId = " + hostedzoneId)

ip=getIpFromRecord(fqdn,hostedzoneId)
if verbose:
  log("VERBOSE ip = " + str(ip))
if ip:
  if dryrun:
    log("DRYRUN Would delete DNS Record \"" + fqdn + "\" (" + ip + ")")
  else:
    log("INFO Deleting DNS Record \"" + fqdn + "\" (" + ip + ")")
    deleteRecord(fqdn,'A',ip,hostedzoneId)
    if getIpFromRecord(fqdn,hostedzoneId):
      log("ERROR DNS Record \"" + fqdn + "\" still exists")
    else:
      log("SUCCESS DNS Record \"" + fqdn + "\" has been deleted")
else:
  log("WARN DNS Record \"" + fqdn + "\" doesn't exist in ZoneId " + hostedzoneId)
