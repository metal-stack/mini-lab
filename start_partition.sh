#!/usr/bin/env bash
set -e

vagrant up
ansible-galaxy install -r control-plane/requirements.yaml --ignore-errors
ansible-playbook -i partition/static_inventory.yaml -i ~/.ansible/roles/ansible-common/inventory/vagrant partition.yaml

vagrant up machine01 machine02