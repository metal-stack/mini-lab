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

# Helper-Function to define a Vagrant VM with a specific box, version and memory
def box(device:, hostname:, box:, box_version:, memory:)
    device.vm.hostname = hostname
    device.vm.box = box
    device.vm.box_version = box_version
    device.vm.provider :libvirt do |v|
      v.memory = memory
    end
end