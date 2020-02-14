#!/usr/bin/env bash

set -e

echo "Starting kind cluster for control-plane"
kind create cluster --config control-plane/kind.yaml --kubeconfig .kubeconfig || true

echo "Starting vagrant boxes for switches of partition"
vagrant up

echo "Deploying control-plane and partition"
docker-compose up

echo "Starting vagrant boxes for machines of partition"
vagrant up machine01 machine02