# Helper-Function to create Libvirt Point-to-Point connections to simulate cables btw. VMs
def cable(device:, iface:, mac:, port:, remote_port:)
device.vm.network "private_network",
    mac: mac,
    libvirt__tunnel_type: 'udp',
    libvirt__tunnel_local_port: port,
    libvirt__tunnel_port: remote_port,
    libvirt__iface_name: iface,
    auto_config: false
end
  
# Helper-Function to define a Vagrant VM as PXE-Device
def pxe(device:, hostname:, memory:, uuid:)
device.vm.hostname = hostname
device.vm.provider :libvirt do |v|
    v.storage :file, size: '6000M', type: 'qcow2', bus: 'sata', device: 'sda'
    v.boot 'network'
    v.boot 'hd'
    v.loader = "/usr/share/OVMF/OVMF_CODE.fd"
    v.mgmt_attach = false
    v.memory = memory
    v.uuid = uuid
end
device.ssh.insert_key = false
end
  
# Helper-Function to defice a Vagrant VM with a specific box, version and memory
def box(device:, hostname:, box:, box_version:, memory:)
    device.vm.hostname = hostname
    device.vm.box = box
    device.vm.box_version = box_version
    device.vm.provider :libvirt do |v|
      v.memory = memory
    end
end
