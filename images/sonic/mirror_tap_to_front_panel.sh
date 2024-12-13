#!/bin/bash

# Script is taken from https://netdevops.me/2021/transparently-redirecting-packetsframes-between-interfaces/
# Read it for better understanding

TAP_IF=$1
# get interface index number up to 3 digits (everything after first three chars)
# tap0 -> 0
# tap123 -> 123
INDEX=${TAP_IF:3:3}

# tap$INDEX corresponds to eth$INDEX in the virtual machine
# The virtual switch assigns lanes to the Linux interface ethX. The assignment is specified in the lanemap.ini file in the following format: ethX:<lanes>.
LANES=$(grep ^eth$INDEX: /lanemap.ini | cut -d':' -f2)
# Identify the front panel using the lanes.
FRONT_PANEL=$(grep -E "^Ethernet[0-9]+\s+$LANES\s+Eth" /port_config.ini | cut -d' ' -f1)

ip link set $TAP_IF up
ip link set $TAP_IF mtu 65000

# create tc Ethernet<->tap redirect rules
tc qdisc add dev $FRONT_PANEL ingress
tc filter add dev $FRONT_PANEL parent ffff: protocol all u32 match u8 0 0 action mirred egress redirect dev $TAP_IF

tc qdisc add dev $TAP_IF ingress
tc filter add dev $TAP_IF parent ffff: protocol all u32 match u8 0 0 action mirred egress redirect dev $FRONT_PANEL
