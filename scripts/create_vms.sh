#!/bin/bash

# Declare mapping: machine name --> machine UUID
declare -A machines
machines['machine01']='e0ab02d2-27cd-5a5e-8efc-080ba80cf258'
machines['machine02']='2294c949-88f6-5390-8154-fa53d93a3313'
machines['machine03']='2a92f14d-d3b1-4d46-b813-5d058103743e'

# Set up VMs
i=1
arr=($MACHINES)
for name in ${arr[@]}; do
  qemu-img create -f qcow2 vdisk${i} 5G

  first=$(($i*2-2))
  second=$(($i*2-1))

  fd1=$(($i*2+1))
  fd2=$(($i*2+2))

  eval "exec $fd1<>/dev/tap$(cat /sys/class/net/macvtap${first}/ifindex)"
  eval "exec $fd2<>/dev/tap$(cat /sys/class/net/macvtap${second}/ifindex)"

  qemu-system-x86_64 \
  -name $name \
  -uuid ${machines[$name]} \
  -m 2G \
  -boot n \
  -drive file="vdisk${i},if=virtio,format=qcow2" \
  -drive if=pflash,format=raw,readonly,file=/usr/share/OVMF/OVMF_CODE.fd \
  -drive if=pflash,format=raw,file=/usr/share/OVMF/OVMF_VARS.fd \
  -net nic,model=virtio,macaddr=$(cat /sys/class/net/macvtap${first}/address) \
  -net tap,fd=$fd1 \
  -net nic,model=virtio,macaddr=$(cat /sys/class/net/macvtap${second}/address) \
  -net tap,fd=$fd2 \
  -serial telnet:127.0.0.1:400$(($i-1)),server,nowait \
  -enable-kvm \
  -nographic &

  i=$(($i+1))
done
