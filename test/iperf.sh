#!/usr/bin/env bash
set -o errexit

echo "Install iperf3"
ssh -o StrictHostKeyChecking=no -o "PubkeyAcceptedKeyTypes +ssh-rsa" -i files/ssh/id_rsa metal@203.0.113.130 "sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install --yes iperf3"
ssh -o StrictHostKeyChecking=no -o "PubkeyAcceptedKeyTypes +ssh-rsa" -i files/ssh/id_rsa metal@203.0.113.131 "sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install --yes iperf3"

echo "Start iperf3 server on machine01"
ssh -o StrictHostKeyChecking=no -o "PubkeyAcceptedKeyTypes +ssh-rsa" -i files/ssh/id_rsa metal@203.0.113.130 "sudo iperf3 --server --one-off --daemon --bind 203.0.113.130"

echo "Run iperf3 test on machine02"
ssh -o StrictHostKeyChecking=no -o "PubkeyAcceptedKeyTypes +ssh-rsa" -i files/ssh/id_rsa metal@203.0.113.131 "iperf3 --client 203.0.113.130"
