#!/usr/bin/env bash
set -e

echo "Cleanup artifacts of previous runs"

make cleanup

sudo ip r d 100.255.254.0/24 || true
