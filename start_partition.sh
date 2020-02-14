#!/usr/bin/env bash
set -e

ansible-galaxy install -r control-plane/requirements.yaml --force
ansible-playbook \
    -i partition/static_inventory.yaml \
    -i ~/.ansible/roles/ansible-common/inventory/vagrant \
    partition.yaml
