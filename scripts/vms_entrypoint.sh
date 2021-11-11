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


ip link add link lan0 name macvtap0 type macvtap mode passthru
ip link set macvtap0 up
ifconfig macvtap0 promisc

ip link add link lan1 name macvtap1 type macvtap mode passthru
ip link set macvtap1 up
ifconfig macvtap1 promisc

ip link add link lan2 name macvtap2 type macvtap mode passthru
ip link set macvtap2 up
ifconfig macvtap2 promisc

ip link add link lan3 name macvtap3 type macvtap mode passthru
ip link set macvtap3 up
ifconfig macvtap3 promisc

ip link add link lan4 name macvtap4 type macvtap mode passthru
ip link set macvtap4 up
ifconfig macvtap4 promisc

ip link add link lan5 name macvtap5 type macvtap mode passthru
ip link set macvtap5 up
ifconfig macvtap5 promisc

echo "Connected all interfaces"
ifdown -a || true
ifup -a || true

tail -f /dev/null
