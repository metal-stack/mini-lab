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

make cleanup

# cleanup orphaned containers; this can occur if a topo file got deleted, as in such a case containerlab will not feel responsible for the containers it created
running_containers=$(docker ps -aq)

for container in $running_containers; do
    labeled=$(docker inspect -f '{{ .Id }} {{ index .Config.Labels "containerlab" }}' $container)
    id=$(echo $labeled | cut -d' ' -f1)
    label=$(echo $labeled | cut -d' ' -f2)
    if [ $label = "mini-lab" ]; then
        echo deleting $id
        docker stop $id
        docker rm $id
    fi
done
