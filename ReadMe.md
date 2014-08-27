## What is this?
For runtime acceptance it is often easier to spin up an bosh-lite AMI instead of running bosh-lite locally on our macbook airs. This script will take a vanilla AWS account and create keypairs/securitygroups and launch a bosh-lite AMI for you. It will then clone cf-release, use a final release or create a dev release and deploy it for you.

syntax: ruby bosh-might.rb <cf-release version number or branch name>

### Setup

export AWS_ACCESS_KEY_ID='...'
export AWS_SECRET_ACCESS_KEY='...'
