#!/usr/bin/env bash
set -e

export KUBECONFIG="$(pwd)/.kubeconfig"
export K8S_AUTH_KUBECONFIG="${KUBECONFIG}"
ansible-galaxy install --ignore-errors -r control-plane/requirements.yaml
ansible-playbook -i control-plane/inventory.yaml control-plane.yaml

stern -n metal-control-plane '.*'