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


ip link add link lan0 name tap0 type macvtap mode passthru
ip link set tap0 up
ifconfig tap0 promisc

ip link add link lan1 name tap1 type macvtap mode passthru
ip link set tap1 up
ifconfig tap1 promisc

ip link add link lan2 name tap2 type macvtap mode passthru
ip link set tap2 up
ifconfig tap2 promisc

ip link add link lan3 name tap3 type macvtap mode passthru
ip link set tap3 up
ifconfig tap3 promisc

echo "Connected all interfaces"
ifdown -a || true
ifup -a || true

tail -f /dev/null
