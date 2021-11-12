#!/bin/bash
for docker_container_id in $(docker ps | grep ignite | awk '{ print $1 }');
do
    echo "deactivate offloading at veth of leaf switch in docker container ${docker_container_id}"
    docker exec "${docker_container_id}" ethtool --offload vm_eth0 tx off
done;
