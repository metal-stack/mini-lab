#!/usr/bin/env bash

# Script is taken from https://netdevops.me/2021/transparently-redirecting-packetsframes-between-interfaces/
# Read it for better understanding

TAP_IF=$1
# tap0 -> 0 ... tap123 -> 123 ; tap$INDEX is guest interface eth$INDEX
INDEX=${TAP_IF:3:3}

# sonic-vpp assigns guest NICs to front panels strictly by their order in
# port_config.ini: guest eth$INDEX is the $INDEX-th front panel. Mirror this tap
# to the clab link (named after that front panel) using the SAME order. This is
# independent of how interface names happen to sort (Ethernet4 vs Ethernet12/16,
# breakout sub-ports, ...), which is what the lanemap-based lookup got wrong.
FRONT_PANEL=$(awk '$1 ~ /^Ethernet/ {print $1}' /port_config.ini | sed -n "${INDEX}p")

if [ -z "$FRONT_PANEL" ]; then
    echo "mirror_tap_to_front_panel: no port_config.ini entry #${INDEX} for ${TAP_IF}" >&2
    exit 1
fi

ip link set "$TAP_IF" up
ip link set "$TAP_IF" mtu 65000

# create tc Ethernet<->tap redirect rules
tc qdisc add dev "$FRONT_PANEL" ingress
tc filter add dev "$FRONT_PANEL" parent ffff: protocol all u32 match u8 0 0 action mirred egress redirect dev "$TAP_IF"

tc qdisc add dev "$TAP_IF" ingress
tc filter add dev "$TAP_IF" parent ffff: protocol all u32 match u8 0 0 action mirred egress redirect dev "$FRONT_PANEL"
