#!/bin/bash

chown root:kvm /dev/kvm
#sudo chmod +666 /dev/kvm

sed -i 's/\#security_driver.*/security_driver\ =\ \"none\"/' /etc/libvirt/qemu.conf
systemctl restart libvirtd

virsh pool-define /dev/stdin <<EOF
<pool type='dir'>
  <name>default</name>
  <target>
    <path>/var/lib/libvirt/images</path>
  </target>
</pool>
EOF

virsh pool-start default
