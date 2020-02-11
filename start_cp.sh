#!/usr/bin/env bash

kind create cluster --config cp/kind.yaml
export ANSIBLE_JINJA2_NATIVE=1
ansible-galaxy install -r cp/requirements.yaml
ansible-playbook -i cp/inventory.yaml cp.yaml
