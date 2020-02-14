#!/usr/bin/env bash

vagrant destroy -f --parallel
kind delete cluster
unlink .kubeconfig