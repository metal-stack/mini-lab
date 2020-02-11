#!/usr/bin/env bash

set -e

vagrant up

LEAF01_SSH_CONFIG=$(vagrant ssh-config leaf01)
export LEAF01_IP=$(echo "${LEAF01_SSH_CONFIG}" | grep HostName | cut -d" " -f4)
export LEAF01_PK=$(echo "${LEAF01_SSH_CONFIG}" | grep IdentityFile | cut -d" " -f4)

LEAF02_SSH_CONFIG=$(vagrant ssh-config leaf02)
export LEAF02_IP=$(echo "${LEAF02_SSH_CONFIG}" | grep HostName | cut -d" " -f4)
export LEAF02_PK=$(echo "${LEAF02_SSH_CONFIG}" | grep IdentityFile | cut -d" " -f4)

cat partition/inventory.yaml.tpl | envsubst > partition/inventory.yaml
