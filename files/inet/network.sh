#!/bin/sh
set -o errexit -o xtrace

ip link add vrfInternet type vrf table 1000
ip link set dev vrfInternet up
ip link set dev ext master vrfInternet

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

ip link add vniInternet type vxlan id 104009 dstport 4789 local 10.0.0.21 nolearning
ip link set dev vniInternet mtu 9000
ip link set dev vniInternet master bridge
bridge vlan del vid 1 dev vniInternet
bridge vlan del vid 1 untagged pvid dev vniInternet
bridge vlan add vid 1000 dev vniInternet
bridge vlan add vid 1000 untagged pvid dev vniInternet
ip link set up dev vniInternet
