#!/bin/bash

set -o errexit
TAP_IF=$1
FROM_IF=$2
TO_IF=$3

tc qdisc del dev $FROM_IF ingress
tc qdisc del dev $TAP_IF ingress

tc qdisc add dev $TO_IF ingress
tc filter add dev $TO_IF parent ffff: protocol all u32 match u8 0 0 action mirred egress redirect dev $TAP_IF

tc qdisc add dev $TAP_IF ingress
tc filter add dev $TAP_IF parent ffff: protocol all u32 match u8 0 0 action mirred egress redirect dev $TO_IF
