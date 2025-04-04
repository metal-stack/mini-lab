#!/usr/bin/env bash
set -e

echo "Cleanup artifacts of previous runs"

# containerlab will figure out previous run locations from the docker containers
running_containers=$(docker ps -aq)

if [ ! -z "$running_containers" ]; then
    previous_topos=$(docker inspect -f '{{ index .Config.Labels "clab-topo-file" }}' $(docker ps -aq))
    for topo in previous_topos; do
        previous_lab_dir=$(dirname $topo)
        mkdir -p "${previous_lab_dir}/clab-mini-lab"
    done
fi

make prune-proxy-registries
make cleanup

echo "Remove containers from previous runs"

previous_mini_lab_containers=$(docker container list --all --filter label=containerlab=mini-lab --quiet)

if [ ! -z "$previous_mini_lab_containers" ]; then
    docker container rm --force $(docker container list --all --filter label=containerlab=mini-lab --quiet)
fi
