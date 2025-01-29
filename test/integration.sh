#!/usr/bin/env bash
set -e

echo "Starting mini-lab"
make up

echo "Waiting for machines to get to waiting state"
waiting=$(docker compose run --no-TTY --rm metalctl machine ls | grep Waiting | wc -l)
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
    waiting=$(docker compose run --no-TTY --rm metalctl machine ls | grep Waiting | wc -l)
    attempts=$attempts+1
done
echo "$waiting/$minWaiting machines are waiting"

echo "Create firewall"
make firewall

echo "Waiting for firewall to get to Phoned Home state"
phoned=$(docker compose run --no-TTY --rm metalctl machine ls | grep Phoned | wc -l)
minPhoned=1
declare -i attempts=0
until [ "$phoned" -ge $minPhoned ]
do
    if [ "$attempts" -ge 120 ]; then
        echo "not enough machines phoned home - timeout reached"
        exit 1
    fi
    echo "$phoned/$minPhoned machines have phoned home"
    sleep 5
    phoned=$(docker compose run --no-TTY --rm metalctl machine ls | grep Phoned | wc -l)
    attempts+=1
done
echo "$phoned/$minPhoned machines have phoned home"

make machine

echo "Waiting for machine to get to Phoned Home state"
phoned=$(docker compose run --no-TTY --rm metalctl machine ls | grep Phoned | wc -l)
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
    phoned=$(docker compose run --no-TTY --rm metalctl machine ls | grep Phoned | wc -l)
    attempts+=1
done
echo "$phoned/$minPhoned machines have phoned home"

echo "Test connectivity to outside"
make test-connectivity-to-external-service

echo "Test connectivity from outside"
public_ip=$(make public-ip)
make ssh-machine COMMAND="sudo ip addr add ${public_ip}/32 dev lo"

for i in $(seq 1 10); do
  if ssh -F files/ssh/config metal@"${public_ip}" -C exit > /dev/null 2>&1; then
    echo "Connected successfully"
    break
  else
    echo "Connection failed"
    if [ $i -lt 10 ]; then
      echo "Retrying in 1 second..."
      sleep 1
    else
      echo "Max retries reached"
      exit 1
    fi
  fi
done

echo "Successfully started mini-lab"
