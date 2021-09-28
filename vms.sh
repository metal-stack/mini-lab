#!/bin/bash

chown root:kvm /dev/kvm
service libvirtd start
service virtlogd start

virsh pool-define /dev/stdin <<EOF
<pool type='dir'>
  <name>default</name>
  <target>
    <path>/var/lib/libvirt/images</path>
  </target>
</pool>
EOF

virsh pool-start default

virsh pool-list
vagrant up

tail -f /dev/null