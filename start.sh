#!/usr/bin/env bash

set -e

./start_partition.sh
sleep 30
./deploy_partition.sh &
./start_cp.sh
fg || true

vagrant up machine01 machine02
