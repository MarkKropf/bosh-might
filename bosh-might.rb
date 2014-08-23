#!/usr/bin/ruby

require 'rubygems'
require 'aws-sdk'

AWS.config(:access_key_id     => ENV['AWS_ACCESS_KEY_ID'],
           :secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'])

ec2                 = AWS::EC2.new
ami_name            = 'ami-ee529e86'
instance_type       = 'm3.xlarge'
ssh_username        = 'ubuntu'

key_pair = ec2.key_pairs.find{|kp| kp.name == 'default' }
if key_pair == nil
  key_pair = ec2.key_pairs.import("default", File.read("#{ENV['HOME']}/.ssh/id_rsa.pub"))
else
  key_pair = ec2.key_pairs['default']
end
puts "Using keypair #{key_pair.name}, fingerprint: #{key_pair.fingerprint}"

security_group = ec2.security_groups.find{|sg| sg.name == 'bosh-lite' }

if security_group == nil
  secgroup = ec2.security_groups.create('bosh-lite')
  secgroup.authorize_ingress(:tcp, 22, '0.0.0.0/0')
else
  secgroup = security_group
  puts "Using security group: #{security_group.name}"
end

# create the instance (and launch it)
instance = ec2.instances.create(:image_id        => ami_name,
                                :instance_type   => instance_type,
                                :count           => 1,
                                :security_groups => secgroup,
                                :key_pair        => key_pair,
                                :block_device_mappings => [
                                  {
                                   :device_name => "/dev/sda1",
                                   :ebs         => { :volume_size => 80, :delete_on_termination => true }
                                  }
                                ])
puts "Launching bosh-lite instance ..."

# wait until battle station is fully operational
sleep 1 until instance.status != :pending
puts "Launched instance #{instance.id}, status: #{instance.status}, public dns: #{instance.dns_name}, public ip: #{instance.ip_address}"
exit 1 unless instance.status == :running

# machine is ready, ssh to it and run a commmand
puts "Launched: You can SSH to it with;"
puts "ssh #{ssh_username}@#{instance.ip_address}"
puts "Remember to terminate after your'e done!"
