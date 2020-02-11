#!/usr/bin/env bash

rm partition/inventory.yaml
vagrant destroy -f --parallel
kind delete cluster