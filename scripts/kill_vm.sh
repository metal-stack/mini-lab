#!/bin/bash
set -eo pipefail

if ps -ef | grep qemu-system-x86_64 | grep $1 > /dev/null 2>&1; then
    PROCESS_ID=$(ps -ef | grep qemu-system-x86_64 | grep $1 | grep -v grep | awk '{ print $2 }')
    echo "killing vm with process ID $PROCESS_ID"
    kill $PROCESS_ID || true
else
    echo "vm not running"
fi
