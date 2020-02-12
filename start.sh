#!/usr/bin/env bash

set -e

./start_partition.sh &
./start_control-plane.sh
fg || true

vagrant up machine01 machine02
