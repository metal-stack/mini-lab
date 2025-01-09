#!/bin/sh
set -o errexit -o xtrace

ip addr add 192.0.2.10/24 dev isp
ip addr add 198.51.100.1/32 dev isp
ip route add 203.0.113.0/24 via 192.0.2.2 dev isp
