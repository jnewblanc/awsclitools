# AWS Route53 cleanup scripts

## removeRoute53Record.py - cleans up obsolete route53 DNS entry
* Accepts a hostname (server name) and hosted zone (domain)
* Looks up Zone ID based on hosted zone (domain)
* Aborts if a non-terminated ec2 instance exists (based on the "Name" tag)
* Aborts if route53 DNS entry doesn't exist
* Deletes route53 record if everything else checks out

```
usage: removeRoute53Record.py <hostname> [--hostedZone hostedzone] [--verbose] [--debug] [--color]
```                            

