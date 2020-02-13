#!/usr/bin/env bash
set -e

ansible-galaxy install -r control-plane/requirements.yaml --force

if [ ! -f partition/dynamic_inventory.sh ]; then
    echo "#!/bin/bash" > partition/dynamic_inventory.sh
    echo "echo '" >> partition/dynamic_inventory.sh
    ~/.ansible/roles/ansible-common/inventory/vagrant/vagrant.py >> partition/dynamic_inventory.sh
    echo "'" >> partition/dynamic_inventory.sh
fi

ansible-playbook \
    -i partition/static_inventory.yaml \
    -i partition/dynamic_inventory.sh \
    partition.yaml
