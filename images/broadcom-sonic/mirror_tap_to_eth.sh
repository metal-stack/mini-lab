#!/bin/bash

# Script is taken from https://netdevops.me/2021/transparently-redirecting-packetsframes-between-interfaces/
# Read it for better understanding

set -o errexit

TAP_IF=$1
# get interface index number up to 3 digits (everything after first three chars)
# tap0 -> 0
# tap123 -> 123
INDEX=${TAP_IF:3:3}

ip link set $TAP_IF up
ip link set $TAP_IF mtu 65000

# create tc eth<->tap redirect rules
tc qdisc add dev eth$INDEX ingress
tc filter add dev eth$INDEX parent ffff: protocol all u32 match u8 0 0 action mirred egress redirect dev $TAP_IF

tc qdisc add dev $TAP_IF ingress
tc filter add dev $TAP_IF parent ffff: protocol all u32 match u8 0 0 action mirred egress redirect dev eth$INDEX
