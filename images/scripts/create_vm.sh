#!/bin/bash
qemu-img create -f qcow2 vdisk1 5G
qemu-img create -f qcow2 vdisk2 5G

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
-nographic &

ip link add link lan2 name macvtap2 type macvtap mode passthru
ip link set macvtap2 up
ifconfig macvtap2 promisc

ip link add link lan3 name macvtap3 type macvtap mode passthru
ip link set macvtap3 up
ifconfig macvtap3 promisc

qemu-system-x86_64 \
-name machine02 \
-uuid 2294c949-88f6-5390-8154-fa53d93a3313 \
-m 2G \
-boot n \
-drive file='vdisk2,if=virtio,format=qcow2' \
-drive if=pflash,format=raw,readonly,file=/usr/share/OVMF/OVMF_CODE.fd \
-drive if=pflash,format=raw,file=/usr/share/OVMF/OVMF_VARS.fd \
-net nic,model=virtio,macaddr=$(cat /sys/class/net/macvtap2/address) \
-net tap,fd=5 5<>/dev/tap$(cat /sys/class/net/macvtap2/ifindex) \
-net nic,model=virtio,macaddr=$(cat /sys/class/net/macvtap3/address) \
-net tap,fd=6 6<>/dev/tap$(cat /sys/class/net/macvtap3/ifindex) \
-enable-kvm \
-nographic