#!/usr/bin/env bash
set -e

echo "Cleanup artifacts of previous runs"

# containerlab will figure out previous run locations from the docker containers
previous_topos=$(docker inspect -f '{{ index .Config.Labels "clab-topo-file" }}' $(docker ps -aq))
for topo in previous_topos; do
    previous_lab_dir=$(dirname $topo)
    mkdir -p "${previous_lab_dir}/clab-mini-lab"
    # destroying the sonic lab requires the image to exist, otherwise it fails with bind path verification
    touch "${previous_lab_dir}/sonic-vs.img"
done

make cleanup

sudo ip r d 100.255.254.0/24 || true
