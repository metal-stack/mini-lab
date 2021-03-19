#!/usr/bin/env bash
set -e

echo "Cleanup artifacts of previous runs"

make cleanup

# cleanup does not work 100% on the CI-runner - use virsh commands directly
for i in metalleaf01 metalleaf02 metalmachine01 metalmachine02 metalmachine03; do \
    virsh destroy $i || true; \
    virsh undefine $i || true; \
    virsh vol-delete --pool default "$i-sda.qcow2" || true; \
    virsh vol-delete --pool default "$i.img" || true; \
done

sudo ip r d 100.255.254.0/24 || true
