#!/usr/bin/env bash

set -e

export TMPDIR=/var/tmp/

echo "Cleanup artifacts of previous runs"
make cleanup

# cleanup does not work 100% on the CI-runner - use virsh commands directly
for i in metalleaf01 metalleaf02 metalmachine01 metalmachine02; do
    virsh destroy $i || true;
    virsh undefine $i || true;
    virsh vol-delete --pool default "$i-sda.qcow2" || true;
    virsh vol-delete --pool default "$i.img" || true;
done

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
sudo ip r d 100.255.254.0/24 || true
$(make route) || true

echo "Check if SSH login to firewall works"
ssh -o StrictHostKeyChecking=no metal@100.255.254.1 -C exit

echo "Successfully started mini-lab"
sudo ip r d 100.255.254.0/24
make cleanup
