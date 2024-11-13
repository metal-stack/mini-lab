#!/usr/bin/env bash
set -eo pipefail

cd gardener-tmp/*

# this is basically taken from the gardener hack directory for creating the controller-registration
helm package charts/gardener/provider-local --destination provider-local-chart-tmp > /dev/null
mkdir -p provider-local-chart
tar -xzm -C provider-local-chart -f provider-local-chart-tmp/*
chart=$(tar --sort=name -c --owner=root:0 --group=root:0 --mtime='UTC 2019-01-01' -C provider-local-chart "$(basename provider-local-chart/*)" | gzip -n | base64 | tr -d '\n')

cd -

echo "gardener_provider_local_raw_chart: ${chart}" > inventories/group_vars/control-plane/gardener/provider_local.yaml
