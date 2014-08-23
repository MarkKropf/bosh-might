## What is this?
For runtime acceptance it is often easier to spin up an bosh-lite AMI instead of running bosh-lite locally on our macbook airs. This script will take a vanilla AWS account and create keypairs/securitygroups and launch a bosh-lite AMI for you.

### Setup

export AWS_ACCESS_KEY_ID='...'
export AWS_SECRET_ACCESS_KEY='...'

### Next Steps

Install golang, spiff
Clone bosh-lite, cf-release
Bosh target, upload stemcell, upload release, deploy
