#!/usr/bin/env bash
set -eo pipefail

ansible-playbook -i inventories/control-plane.yaml obtain_role_requirements.yaml
ansible-galaxy install --ignore-errors -r requirements.yaml

ansible-playbook -i inventories/control-plane.yaml -i ~/.ansible/roles/metal-ansible-modules/inventory/metal.py integration.yaml
