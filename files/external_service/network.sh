#!/bin/sh
set -o errexit -o xtrace

ip addr add 203.0.113.10/24 dev mini_lab_ext
ip route add 203.0.113.0/24 via 192.0.2.2 dev mini_lab_ext
