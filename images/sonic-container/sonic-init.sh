#!/bin/sh
set -eu

# docker bind-mounts /etc/resolv.conf, /etc/hostname and /etc/hosts, which
# breaks ansible modules that replace files via atomic rename, so
# turn them into regular files
make_regular_file() {
    mountpoint -q "$1" || return 0
    cp "$1" "$1.unmounted"
    umount "$1"
    mv "$1.unmounted" "$1"
}

wait_for_interfaces() {
    # Recovers the number of containerlab interfaces, then waits until all interfaces are ready
	# necessary in this image because we replace PID 1 with systemd
    clab_intfs=$(tr '\0' '\n' </proc/1/environ | sed -n 's/^CLAB_INTFS=//p')
    expected=$((${clab_intfs:-0} + 1))

    echo "waiting for ${expected} interfaces to be connected"
    while [ "$(ls -d /sys/class/net/eth* 2>/dev/null | wc -l)" -lt "${expected}" ]; do
        sleep 1
    done
}

# seed the initial config_db. sonic-config regenerates this file later, so it
# must be a copy rather than a bind mount at the target path
seed_config_db() {
    [ ! -f /etc/sonic/config_db.json ] || return 0
    [ -f /config_db.json.init ] || return 0

    mkdir -p /etc/sonic
    mac=$(cat /sys/class/net/eth0/address)
    jq --arg mac "${mac}" '.DEVICE_METADATA.localhost.mac = $mac' \
        /config_db.json.init >/etc/sonic/config_db.json
}

install_root_ssh_key() {
    [ -f /authorized_keys ] || return 0

    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    cp /authorized_keys /root/.ssh/authorized_keys
    chown root:root /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
}

for f in /etc/resolv.conf /etc/hostname /etc/hosts; do
    make_regular_file "${f}"
done
wait_for_interfaces
seed_config_db
install_root_ssh_key
