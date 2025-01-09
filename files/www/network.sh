#!/bin/sh
set -o errexit -o xtrace

ip addr add 203.0.113.3/24 dev ext
ip route add 203.0.113.128/25 via 203.0.113.2 dev ext
