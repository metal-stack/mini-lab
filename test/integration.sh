#!/usr/bin/env bash
set -e

echo "Starting mini-lab"
make up

echo "Waiting for machines to get to waiting state"
waiting=$(docker compose run -T metalctl machine ls | grep Waiting | wc -l)
minWaiting=2
declare -i attempts=0
until [ "$waiting" -ge $minWaiting ]
do
    if [ "$attempts" -ge 60 ]; then
        echo "not enough machines in waiting state - timeout reached"
        exit 1
    fi
    echo "$waiting/$minWaiting machines are waiting"
    sleep 5
    waiting=$(docker compose run -T metalctl machine ls | grep Waiting | wc -l)
    attempts=$attempts+1
done
echo "$waiting/$minWaiting machines are waiting"

echo "Create firewall and machine"
make firewall
make machine

echo "Waiting for machines to get to Phoned Home state"
phoned=$(docker compose run -T metalctl machine ls | grep Phoned | wc -l)
minPhoned=2
declare -i attempts=0
until [ "$phoned" -ge $minPhoned ]
do
    if [ "$attempts" -ge 120 ]; then
        echo "not enough machines phoned home - timeout reached"
        exit 1
    fi
    echo "$phoned/$minPhoned machines have phoned home"
    sleep 5
    phoned=$(docker compose run -T metalctl machine ls | grep Phoned | wc -l)
    attempts+=1
done
echo "$phoned/$minPhoned machines have phoned home"

sleep 10

echo "Test connectivity to outside"
make connect-to-cloudflare

echo "Check if SSH login to firewall works"
ssh -o StrictHostKeyChecking=no -o "PubkeyAcceptedKeyTypes +ssh-rsa" -i files/ssh/id_rsa metal@203.0.113.129 -C exit

echo "Successfully started mini-lab"
