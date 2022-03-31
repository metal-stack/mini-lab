#!/bin/bash
set -eo pipefail

# first check if CLAB_INTFS is configured (containerlab's metadata var), defaulting to 0
INTFS=${CLAB_INTFS:-0}

# next check if the argument was provided which can override the above
INTFS=${1:-$INTFS}

echo "Waiting for $INTFS interfaces to be connected"
int_calc ()
{
    index=0
    for i in $(ls -1v /sys/class/net/ | grep 'eth\|ens\|eno\|lan' | grep -v eth0); do
      let index=index+1
    done
    MYINT=$index
}

int_calc

while [ "$MYINT" -lt "$INTFS" ]; do
  echo "Connected $MYINT interfaces out of $INTFS"
  sleep 1
  int_calc
done

# creating macvtap interfaces for the qemu vms
#for i in $(seq 0 5); do
#  ip link add link lan${i} name macvtap${i} type macvtap mode passthru
#  ip link set macvtap${i} up
#  ip link set macvtap${i} promisc on
#done

echo "Connected all interfaces"
ifdown -a || true
ifup -a || true

tail -f /dev/null
