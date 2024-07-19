#!/bin/sh
set -o errexit -o xtrace

ip link add vrfInternet type vrf table 1000
ip link set dev vrfInternet up
ip link set dev ext master vrfInternet

# IPv6
ip link add vrfInternet6 type vrf table 1006
ip link set dev vrfInternet6 up
ip link set dev eth0 master vrfInternet6

ip link add name bridge type bridge stp_state 0
ip link set dev bridge type bridge vlan_filtering 1
ip link set dev bridge mtu 9000
ip link set dev bridge up

ip link add link bridge up name vlanInternet type vlan id 1000
ip link set dev vlanInternet mtu 9000
ip link set dev vlanInternet master vrfInternet
bridge vlan del vid 1 dev bridge self
bridge vlan add vid 1000 dev bridge self
ip link set dev vlanInternet up

# IPv6
ip link add link bridge up name vlanInternet6 type vlan id 1006
ip link set dev vlanInternet6 mtu 9000
ip link set dev vlanInternet6 master vrfInternet6
bridge vlan add vid 1006 dev bridge self
ip link set dev vlanInternet6 up

ip link add vniInternet type vxlan id 104009 dstport 4789 local 10.0.0.21 nolearning
ip link set dev vniInternet mtu 9000
ip link set dev vniInternet master bridge
bridge vlan del vid 1 dev vniInternet
bridge vlan del vid 1 untagged pvid dev vniInternet
bridge vlan add vid 1000 dev vniInternet
bridge vlan add vid 1000 untagged pvid dev vniInternet
ip link set up dev vniInternet

# IPv6
ip link add vniInternet6 type vxlan id 106009 dstport 4789 local 10.0.0.21 nolearning
ip link set dev vlanInternet6 mtu 9000
ip link set dev vniInternet6 master bridge
bridge vlan del vid 1 dev vniInternet6
bridge vlan del vid 1 untagged pvid dev vniInternet6
bridge vlan add vid 1006 dev vniInternet6
bridge vlan add vid 1006 untagged pvid dev vniInternet6
ip link set up dev vniInternet6

# Does not have a ipv6 address on eth0 on startup, fix this
ip ad add 2001:db8:1::42/64 dev eth0

iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
