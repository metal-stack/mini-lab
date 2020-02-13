#!/usr/bin/env bash

set -e

kind create cluster --config control-plane/kind.yaml --kubeconfig .kubeconfig || true
vagrant up

docker-compose up