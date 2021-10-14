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
    libvirt.management_network_address = "172.17.0.0/24"
    libvirt.management_network_mtu = 1500
    libvirt.nic_adapter_count = 130
  end
  config.vm.define "machine01" do |device|
    pxe device: device, hostname: "machine01", memory: 2000, uuid: "e0ab02d2-27cd-5a5e-8efc-080ba80cf258"
    device.vm.network "public_network", dev: "lan0", mode: "passthrough", trust_guest_rx_filters: true
    device.vm.network "public_network", dev: "lan1", mode: "passthrough", trust_guest_rx_filters: true
  end
  config.vm.define "machine02" do |device|
    pxe device: device, hostname: "machine02", memory: 2000, uuid: "2294c949-88f6-5390-8154-fa53d93a3313"
    device.vm.network "public_network", dev: "lan2", mode: "passthrough", trust_guest_rx_filters: true
    device.vm.network "public_network", dev: "lan3", mode: "passthrough", trust_guest_rx_filters: true
  end
end