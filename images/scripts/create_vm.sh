#!/bin/bash
qemu-img create -f qcow2 vdisk1 5G

ip link add link lan0 name macvtap0 type macvtap mode passthru
ip link set macvtap0 up
ifconfig macvtap0 promisc

ip link add link lan1 name macvtap1 type macvtap mode passthru
ip link set macvtap1 up
ifconfig macvtap1 promisc

qemu-system-x86_64 \
-name machine01 \
-uuid e0ab02d2-27cd-5a5e-8efc-080ba80cf258 \
-m 2G \
-boot n \
-drive file='vdisk1,if=virtio,format=qcow2' \
-drive if=pflash,format=raw,readonly,file=/usr/share/OVMF/OVMF_CODE.fd \
-drive if=pflash,format=raw,file=/usr/share/OVMF/OVMF_VARS.fd \
-net nic,model=virtio,macaddr=$(cat /sys/class/net/macvtap0/address) \
-net tap,fd=3 3<>/dev/tap$(cat /sys/class/net/macvtap0/ifindex) \
-net nic,model=virtio,macaddr=$(cat /sys/class/net/macvtap1/address) \
-net tap,fd=4 4<>/dev/tap$(cat /sys/class/net/macvtap1/ifindex) \
-enable-kvm \
-nographic \
;