#!/usr/bin/env bash
set -e

kind create cluster --config control-plane/kind.yaml || true
export ANSIBLE_JINJA2_NATIVE=1
ansible-galaxy install --ignore-errors -r control-plane/requirements.yaml
ansible-playbook -i control-plane/inventory.yaml control-plane.yaml
