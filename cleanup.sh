#!/usr/bin/env bash

vagrant destroy -f --parallel
kind delete cluster
unlink .kubeconfig
unlink .ansible_vagrant_cache