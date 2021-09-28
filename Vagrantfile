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
  config.vm.define "machine01" do |device|
    pxe device: device, hostname: "machine01", memory: 2000, uuid: "e0ab02d2-27cd-5a5e-8efc-080ba80cf258"
    device.vm.network "public_network", dev: "virbr0"
    device.vm.network "public_network", dev: "virbr0"
  end
end