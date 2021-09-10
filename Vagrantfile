#to UNIX EOL
# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# specifies the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.

# This file is built from the great work of Cristina Muñoz over at
# https://github.com/PermanentOrg/devenv

Vagrant.configure(2) do |config|
  # The most common configuration options are documented and commented below.
  # For a complete reference, please see the online documentation at
  # https://docs.vagrantup.com.

  # Every Vagrant development environment requires a box. You can search for
  # boxes at https://app.vagrantup.com/boxes/search or even make your own using
  # the steps outlined at https://www.vagrantup.com/vagrant-cloud/boxes/create.
  config.vm.box = "generic/debian11"
  config.vm.box_version = "3.4.2"
  config.vm.define "lever-for-change"

  # Disable automatic box update checking. If you disable this, then
  # boxes will only be checked for updates when the user runs
  # `vagrant box outdated`. This is not recommended.
  config.vm.box_check_update = true

  # Create a forwarded port mapping which allows access to a specific port
  # within the machine from a port on the host machine. In the example below,
  # accessing "localhost:8080" will access port 80 on the guest machine.

  # Create a private network, which allows host-only access to the machine
  # using a dynamic IP in order to avoid potential network conflicts.
  config.vm.network "private_network", type: "dhcp"
  config.vm.network "forwarded_port", guest: 80, host: 80
  config.vm.network "forwarded_port", guest: 5000, host: 5000

  # Share additional folders to the guest VM. The first argument is
  # the path on the host to the actual folder. The second argument is
  # the path on the guest to mount the folder. And the optional third
  # argument is a set of non-required options.
  config.vm.synced_folder "../torque-sites", "/home/vagrant/torque-sites", owner: "vagrant", group: "vagrant"
  config.vm.synced_folder "../data", "/home/vagrant/data", owner: "vagrant", group: "vagrant"
  config.vm.synced_folder "../SimpleBook", "/home/vagrant/SimpleBook", owner: "vagrant", group: "vagrant"
  config.vm.synced_folder "./configuration", "/home/vagrant/configuration", owner: "vagrant", group: "vagrant"

  # Provider-specific configuration so you can fine-tune various
  # backing providers for Vagrant. These expose provider-specific options.
  # Example for VirtualBox:
  #
  config.vm.provider "virtualbox" do |vb|
    vb.customize ["modifyvm", :id, "--ioapic", "on"]
    vb.memory = "4096"
    vb.cpus = 2
    vb.linked_clone = true
  end

  # Enable provisioning with a shell script. Additional provisioners such as
  # Puppet, Chef, Ansible, Salt, and Docker are also available. Please see the
  # documentation for more information about their specific syntax and use.
  config.vm.provision "file", source: "templates", destination: "/tmp/templates"
  config.vm.provision "shell", path: "configure.sh",
    env: {"APP_USER": "vagrant",
          "TEMPLATES_PATH": "/tmp/templates"}

  # IMPORTANT: escape characters MUST BE DOUBLE ESCAPED when writing an inline script.
  # If this script is ever moved to a file, the double escapes must be removed.
  config.vm.provision "shell", run: "always", inline: <<-SHELL
	  echo "Finished and running at:"
	  ip -4 addr show eth1 | grep -oP '(?<=inet\\s)\\d+(\\.\\d+){3}'
	SHELL
end
