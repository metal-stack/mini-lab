#!/usr/bin/env bash

rm leaves/inventory.yaml
vagrant destroy -f --parallel
kind delete cluster