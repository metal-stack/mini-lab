#!/usr/bin/env bash

kind create cluster --config control-plane/kind.yaml
export ANSIBLE_JINJA2_NATIVE=1
ansible-galaxy install -r control-plane/requirements.yaml
ansible-playbook -i control-plane/inventory.yaml control-plane.yaml
