#!/usr/bin/env bash
set -e

echo "Starting mini-lab"
make up

echo "Waiting for machines to get to waiting state"
waiting=$(docker-compose run metalctl machine ls | grep Waiting | wc -l)
minWaiting=2
until [ "$waiting" -ge $minWaiting ]
do
    echo "$waiting/$minWaiting machines are waiting"
    sleep 5
    waiting=$(docker-compose run metalctl machine ls | grep Waiting | wc -l)
done
echo "$waiting/$minWaiting machines are waiting"

echo "Create machine and firewall"
make machine
make firewall

echo "Waiting for machines to get to Phoned Home state"
phoned=$(docker-compose run metalctl machine ls | grep Phoned | wc -l)
minPhoned=2
until [ "$phoned" -ge $minPhoned ]
do
    echo "$phoned/$minPhoned machines have phoned home"
    sleep 5
    phoned=$(docker-compose run metalctl machine ls | grep Phoned | wc -l)
done
echo "$phoned/$minPhoned machines have phoned home"

sleep 10

echo "Adding route to leaf01"
make route

# FIXME: is still flaky somehow. :(
# echo "Check if SSH login to firewall works"
# ssh -o StrictHostKeyChecking=no metal@100.255.254.1 -C exit

echo "Successfully started mini-lab"
