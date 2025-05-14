#!/bin/bash

# Script is taken from https://netdevops.me/2021/transparently-redirecting-packetsframes-between-interfaces/
# Read it for better understanding

set -o errexit

TAP_IF=$1
# get interface index number up to 3 digits (everything after first three chars)
# tap0 -> 0
# tap123 -> 123
INDEX=${TAP_IF:3:3}

tc qdisc del dev $TAP_IF ingress
tc qdisc del dev lan$INDEX ingress
