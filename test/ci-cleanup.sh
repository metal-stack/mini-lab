#!/usr/bin/env bash
set -e

echo "Installing containerlab"
bash -c "$(curl -sL https://get-clab.srlinux.dev)"

echo "Cleanup artifacts of previous runs"

sudo rm -rf /var/lib/gitlab-runner/github/_work/mini-lab/mini-lab/clab-mini-lab

make cleanup

# cleanup does not work 100% on the CI-runner - use virsh commands directly
for i in metalleaf01 metalleaf02 metalmachine01 metalmachine02 metalmachine03; do \
    virsh destroy $i || true; \
    virsh undefine $i || true; \
    virsh vol-delete --pool default "$i-sda.qcow2" || true; \
    virsh vol-delete --pool default "$i.img" || true; \
done

sudo ip r d 100.255.254.0/24 || true
