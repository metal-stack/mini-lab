#!/bin/sh
set -o errexit -o xtrace

ip link add vrfInternet type vrf table 1000
ip link set dev vrfInternet up
ip link set dev mini_lab_ext master vrfInternet

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

sysctl -w net.ipv6.conf.all.forwarding=1

# PXE egress return-path NAT. Traffic reaching us over the fabric keeps its original source --
# machines are 10.0.1.0/24, and the leaves' own traffic is sourced from their 10.0.0.0/24
# loopbacks. The mgmt docker bridge only NATs 172.42.0.0/16, so anything we forward out eth0 must
# be SNAT'd or the replies have no path back. Masquerade the whole interface rather than a single
# prefix, so both the machine and leaf-originated ranges are covered.
# The frr image ships no iptables; bounded + non-fatal on purpose, since this script runs under
# `set -o errexit` and must never block exit bring-up if the package mirror is unreachable.
for _ in 1 2 3 4 5; do
	if apk add --no-cache iptables; then
		iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
		break
	fi
	echo "apk could not reach the mirror (iptables); retrying ..."
	sleep 2
done || true
