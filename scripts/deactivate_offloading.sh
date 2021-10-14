#!/bin/bash
for i in $(sudo ignite ps | grep leaf | cut -c1-16);
do
    docker_container_id=$(sudo ignite inspect vm $i | jq -r '.status.runtime.id' | cut -c1-12)
    echo "deactivate offloading at veth of leaf switch in docker container ${docker_container_id}"
    docker exec "${docker_container_id}" ethtool --offload vm_eth0 tx off
done;
