#!/bin/sh
set -o errexit -o xtrace

ip addr add 203.0.113.100/24 dev mini_lab_ext
ip route add 203.0.113.128/25 via 203.0.113.128 dev mini_lab_ext
ip -6 addr add 2001:db8::10/48 dev mini_lab_ext
ip -6 route add 2001:db8:0:113::/64 via 2001:db8:0:1::1 dev mini_lab_ext
