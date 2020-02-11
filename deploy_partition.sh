#!/usr/bin/env bash
export ANSIBLE_JINJA2_NATIVE=1
ansible-galaxy install -r control-plane/requirements.yaml --ignore-errors
ansible-playbook -i partition/inventory.yaml partition.yaml --tags metal-core,docker-on-cumulus