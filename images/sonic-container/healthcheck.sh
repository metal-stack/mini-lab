#!/bin/bash
# Healthy once redis answers and every configured port is oper up in APPL_DB.
# Containerlab's healthy stage blocks the deploy (and with it the Ansible
# provisioning) until then, like the LLDP-based readiness check of the VM
# flavor did.
set -eu

sonic-db-cli PING | grep -q PONG

ports=$(sonic-db-cli CONFIG_DB KEYS 'PORT|*')
[ -n "${ports}" ] || exit 1

for port in ${ports}; do
    port=${port#PORT|}
    status=$(sonic-db-cli APPL_DB HGET "PORT_TABLE:${port}" oper_status)
    if [ "${status}" != "up" ]; then
        echo "${port} is not oper up"
        exit 1
    fi
done
