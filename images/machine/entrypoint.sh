#!/bin/bash

set -o errexit -o pipefail

INTFS=${CLAB_INTFS:-0}

echo "Creating disk with size $QEMU_DISK_SIZE"

qemu-img create -f qcow2 /disk.img ${QEMU_DISK_SIZE}

echo "Waiting for $INTFS interfaces to be connected"

count_interfaces() {
    ls -1v /sys/class/net/ | grep -E 'lan' | wc -l
}

while [ "$(count_interfaces)" -lt "$INTFS" ]; do
    echo "Connected $(count_interfaces) interfaces out of $INTFS"
    sleep 1
done

exec /usr/bin/ipmi_sim -c /openipmi/lan.conf -f /openipmi/ipmisim1.emu
