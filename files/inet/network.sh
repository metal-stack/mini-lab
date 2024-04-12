#!/bin/sh
set -o errexit -o xtrace

ip link add vrf104009 type vrf table 1000
ip link set dev vrf104009 up
ip link set dev eth0 master vrf104009

ip link add name bridge type bridge stp_state 0
ip link set dev bridge type bridge vlan_filtering 1
ip link set dev bridge mtu 9000
ip link set dev bridge up

ip link add link bridge up name vlan104009 type vlan id 1000
ip link set dev vlan104009 mtu 9000
ip link set dev vlan104009 master vrf104009
bridge vlan del vid 1 dev bridge self
bridge vlan add vid 1000 dev bridge self
ip link set dev vlan104009 up

ip link add vni104009 type vxlan id 104009 dstport 4789 local 10.0.0.21 nolearning
ip link set dev vlan104009 mtu 9000
ip link set dev vni104009 master bridge
bridge vlan del vid 1 dev vni104009
bridge vlan del vid 1 untagged pvid dev vni104009
bridge vlan add vid 1000 dev vni104009
bridge vlan add vid 1000 untagged pvid dev vni104009
ip link set up dev vni104009

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
