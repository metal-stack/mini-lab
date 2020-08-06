#!/usr/bin/env bash

set -e

export TMPDIR=/var/tmp/
echo "Starting mini-lab"
make up

echo "Waiting for machines to get to waiting state"
waiting=$(docker-compose run metalctl machine ls | grep Waiting | wc -l)
minWaiting=2
until [ $waiting -ge $minWaiting ]
do
    echo "$waiting/$minWaiting machines are waiting"
    sleep 5
    waiting=$(docker-compose run metalctl machine ls | grep Waiting | wc -l)
done

echo "Create machines"
make machine
make machine

echo "Waiting for machines to get to Phoned Home state"
phoned=$(docker-compose run metalctl machine ls | grep Phoned | wc -l)
minPhoned=2
until [ $phoned -ge $minPhoned ]
do
    echo "$phoned/$minPhoned machines have phoned home"
    sleep 5
    phoned=$(docker-compose run metalctl machine ls | grep Phoned | wc -l)
done

echo "successfully started mini-lab"
make down