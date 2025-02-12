#!/bin/sh
set -o errexit -o xtrace

ip addr add 203.0.113.100/24 dev mini_lab_ext
ip route add 203.0.113.128/25 via 203.0.113.128 dev mini_lab_ext
