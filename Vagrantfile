#  Libvirt Start Port: 8000
#  Libvirt Port Gap: 1000
Vagrant.require_version ">= 2.2.2"
ENV['VAGRANT_DEFAULT_PROVIDER'] = 'libvirt'
# Check required plugins
REQUIRED_PLUGINS_LIBVIRT = %w(vagrant-libvirt)
exit unless REQUIRED_PLUGINS_LIBVIRT.all? do |plugin|
  Vagrant.has_plugin?(plugin) || (
    puts "The #{plugin} plugin is required. Please install it with:"
    puts "$ vagrant plugin install #{plugin}"
    false
  )
end
load File.expand_path('./vagrant/Vagrantfile.helpers.rb')
Vagrant.configure("2") do |config|
  config.vm.synced_folder ".", "/vagrant", type: "rsync", disabled: true
  config.vm.provider :libvirt do |libvirt|
    libvirt.keymap = 'de'
    libvirt.cpus = 1
    libvirt.memory = 1024
    libvirt.random :model => 'random'
    libvirt.default_prefix = 'metal'
    libvirt.management_network_address = "192.168.121.0/24"
    libvirt.nic_adapter_count = 130
  end
  config.vm.define "leaf02" do |device|
    box device: device, hostname: "leaf02", box: "CumulusCommunity/cumulus-vx", box_version: "3.7.13", memory: 512
    cable device: device, iface: "swp1", mac: "44:38:39:00:00:04", port: "9003", remote_port: "8003" # -> lan1@machine01
    cable device: device, iface: "swp2", mac: "44:38:39:00:00:19", port: "9017", remote_port: "8017" # -> lan1@machine02
    device.vm.provision :shell , path: "./vagrant/provision/config_switch.sh"
    device.vm.provision :shell , path: "./vagrant/provision/udev_leaf02.sh"
    device.vm.provision :shell , path: "./vagrant/provision/common.sh"
  end
  config.vm.define "leaf01" do |device|
    box device: device, hostname: "leaf01", box: "CumulusCommunity/cumulus-vx", box_version: "3.7.13", memory: 512
    cable device: device, iface: "swp1", mac: "44:38:39:00:00:1a", port: "9018", remote_port: "8018" # -> lan0@machine01
    cable device: device, iface: "swp2", mac: "44:38:39:00:00:18", port: "9016", remote_port: "8016" # -> lan0@machine02
    device.vm.provision :shell , path: "./vagrant/provision/config_switch.sh"
    device.vm.provision :shell , path: "./vagrant/provision/udev_leaf01.sh"
    device.vm.provision :shell , path: "./vagrant/provision/common.sh"
  end
  config.vm.define "machine01", autostart: false do |device|
    pxe device: device, hostname: "machine01", memory: 1536, uuid: "e0ab02d2-27cd-5a5e-8efc-080ba80cf258"
    cable device: device, iface: "lan0", mac: "00:04:00:11:11:01", port: "8018", remote_port: "9018" # -> swp1@leaf01
    cable device: device, iface: "lan1", mac: "00:04:00:11:12:01", port: "8003", remote_port: "9003" # -> swp1@leaf02
  end
  config.vm.define "machine02", autostart: false do |device|
    pxe device: device, hostname: "machine02", memory: 1536, uuid: "2294c949-88f6-5390-8154-fa53d93a3313"
    cable device: device, iface: "lan0", mac: "00:04:00:22:21:02", port: "8016", remote_port: "9016" # -> swp2@leaf01
    cable device: device, iface: "lan1", mac: "00:04:00:22:22:02", port: "8017", remote_port: "9017" # -> swp2@leaf02
  end
end