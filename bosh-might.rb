#!/usr/bin/ruby

require 'rubygems'
require 'aws-sdk'
require 'colored'
require 'open4'

AWS.config(:access_key_id     => ENV['AWS_ACCESS_KEY_ID'],
           :secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'])

ec2                 = AWS::EC2.new
cf_release_version  = ARGV[0]
ami_name            = `curl -s https://bosh-lite-build-artifacts.s3.amazonaws.com/ami/bosh-lite-ami.list |tail -1`.chop
instance_type       = 'm3.xlarge'
$ssh_username       = 'ubuntu'
$prefix              = "bosh-might".blue_on_black + ": ".yellow

class String
    def integer?
      [                          # In descending order of likeliness:
        /^[-+]?[1-9]([0-9]*)?$/, # decimal
        /^0[0-7]+$/,             # octal
        /^0x[0-9A-Fa-f]+$/,      # hexadecimal
        /^0b[01]+$/              # binary
      ].each do |match_pattern|
        return true if self =~ match_pattern
      end
      return false
    end
  end

def term_out(arg,newline=true)
  if newline
    nl = "\n"
  else
    nl = ""
  end
  print $prefix + arg.white + nl
end

if cf_release_version == nil
  puts "syntax: ruby bosh-might.rb <cf-release version number or branch name>"
  exit
end

key_pair = ec2.key_pairs.find{|kp| kp.name == 'default' }
if key_pair == nil
  key_pair = ec2.key_pairs.import("default", File.read("#{ENV['HOME']}/.ssh/id_rsa.pub"))
else
  key_pair = ec2.key_pairs['default']
end
term_out "Using keypair #{key_pair.name}, fingerprint: #{key_pair.fingerprint}"

security_group = ec2.security_groups.find{|sg| sg.name == 'bosh-lite' }

if security_group == nil
  secgroup = ec2.security_groups.create('bosh-lite')
  secgroup.authorize_ingress(:tcp, 22, '0.0.0.0/0')
else
  secgroup = security_group
  term_out "Using security group: #{security_group.name}"
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
term_out "Launching bosh-lite instance ..."
sleep 1 until instance.status != :pending
term_out "Launched instance #{instance.id}, status: #{instance.status}, public dns: #{instance.dns_name}, public ip: #{instance.ip_address}"
exit 1 unless instance.status == :running
sleep 5
$ip_address = instance.ip_address

def ssh_command(arg, output=false)
  if output
    suffix = ""
  else
    suffix = "> /dev/null 2>&1"
  end
  res = Open4::popen4("ssh -o \"StrictHostKeyChecking no\" #{$ssh_username}@#{$ip_address} 'export DEBIAN_FRONTEND=\"noninteractive\"; #{arg} #{suffix}'") do |pid, stdin, stdout, stderr|
    if stdout.read.strip.include? 'Connection refused'
      print "."
      sleep 5
      ssh_command arg
    end
  end
end

term_out "Attempting to SSH to instance",false
ssh_command "sudo apt-get -y update"
ssh_command "sudo apt-get -y update" #gotta fix this hack
term_out "!"
term_out "Install Git, libmysql, libpq"
ssh_command "sudo apt-get -q -y install git libmysqlclient-dev libpq-dev"
term_out "Install Bundler"
ssh_command "sudo gem install bundler --no-rdoc --no-ri"
term_out "Install Bosh CLI"
ssh_command "sudo gem install bosh_cli --no-rdoc --no-ri"
term_out "Creating workspace directory"
ssh_command "mkdir workspace"
term_out "Installing unzip"
ssh_command "sudo apt-get -q -y install unzip"
term_out "Download Spiff"
ssh_command "wget https://github.com/cloudfoundry-incubator/spiff/releases/download/v1.0/spiff_linux_amd64.zip -P ~/workspace/"
term_out "Install Spiff"
ssh_command "sudo unzip -oq ~/workspace/spiff_linux_amd64.zip -d /usr/local/bin/"
term_out "Cloning into CF-Release"
ssh_command "git clone https://www.github.com/cloudfoundry/cf-release ./workspace/cf-release"
term_out "Target local bosh-lite"
ssh_command "bosh -n target 127.0.0.1"
ssh_command "bosh -n login admin admin"
term_out "Download bosh-lite stemcell"
#TODO: should have a way to get the latest bosh-lite stemcell and download it instead of hard coding it
ssh_command "bosh download public stemcell bosh-stemcell-21-warden-boshlite-ubuntu-trusty-go_agent.tgz", true
term_out "Upload bosh-lite stemcell"
ssh_command "bosh upload stemcell bosh-stemcell-21-warden-boshlite-ubuntu-trusty-go_agent.tgz"
term_out "Upload Bosh Release"
if cf_release_version.integer?
  ssh_command "cd ~/workspace/cf-release; git checkout v#{cf_release_version}"
  ssh_command "cd ~/workspace/cf-release/; ./update"
  ssh_command "cd ~/workspace/cf-release; bosh -n upload release ./releases/cf-#{cf_release_version}.yml"
else
  ssh_command "cd ~/workspace/cf-release; git checkout #{cf_release_version}"
  ssh_command "cd ~/workspace/cf-release/; ./update"
  ssh_command "cd ~/workspace/cf-release; bosh -n create release"
  ssh_command "cd ~/workspace/cf-release; bosh -n upload release"
end
term_out "Spiff manifest"
ssh_command "cd ~/workspace/cf-release; ./bosh-lite/make_manifest"
term_out "Bosh Deploy"
ssh_command "bosh -n deploy", true

term_out "Launched: You can SSH to it with;"
term_out "ssh #{$ssh_username}@#{instance.ip_address}"
term_out "Remember to terminate after your'e done!"
