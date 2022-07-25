#!/bin/bash
set -o nounset

echo "Waiting for $CLAB_INTFS interfaces to be connected"

while true; do
  CONNECTED_INTFS=$(ls -1 /sys/class/net/ | grep --count --regexp 'eth[1-9]')
  echo "Connected $CONNECTED_INTFS interfaces out of $CLAB_INTFS"
  if [ "${CONNECTED_INTFS:-0}" -eq "$CLAB_INTFS" ]; then
    break
  fi
  sleep 1
done

set -o errexit

DISK_IMAGE=/overlay.img
QEMU_NETWORK=""

for i in $(seq 0 $CLAB_INTFS); do
  MAC=$(cat /sys/class/net/eth$i/address | tr -d '\n')
  QEMU_NETWORK="${QEMU_NETWORK} -device virtio-net,netdev=hn$i,mac=${MAC}"
  QEMU_NETWORK="${QEMU_NETWORK} -netdev tap,id=hn$i,ifname=tap$i,script=/mini-lab/mirror_tap_to_eth.sh,downscript=no"
done

qemu-img create -f qcow2 -b /sonic-vs.img "${DISK_IMAGE}"

exec qemu-system-x86_64 \
  -name "${CLAB_LABEL_CLAB_NODE_NAME}" \
  -m 2048 \
  -machine q35 \
  -cpu host \
  -display none \
  -drive if=virtio,format=qcow2,file=overlay.img \
  -enable-kvm \
  ${QEMU_NETWORK}
