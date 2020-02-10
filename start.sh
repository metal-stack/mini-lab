#!/usr/bin/env bash

set -e

./start_leaves.sh
./deploy_leaves.sh &
./start_cp.sh
fg || true

vagrant up machine01 machine02
