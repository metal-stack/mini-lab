# Container SONiC (docker-sonic-vs) image for the container_sonic flavor.
#
# The official docker-sonic-vs image runs all SONiC daemons under a single
# supervisord and ships without sshd, dockerd and systemd. mini-lab deploys
# metal-core, dhcp, pixiecore and the monitoring exporters onto the switches
# via Ansible over SSH as systemd-managed docker containers, so this image adds
#   - systemd as PID 1 with supervisord wrapped in sonic.service
#   - sshd with root key login (authorized_keys installed by sonic-init.sh)
#   - dockerd (docker in docker, requires a privileged container)
#   - lldpd (docker-sonic-vs ships without any LLDP daemon
#   - stub units (bgp/database/syncd/swss.service, sonic.target) so the
#     dependencies of metal-core's generated systemd unit resolve
ARG SONIC_BASE_URL=https://sonic-build.azurewebsites.net/api/sonic/artifacts?branchName=202505&platform=vs
ARG FRR_RELOAD_URL=${SONIC_BASE_URL}&target=target%2Fdebs%2Fbookworm%2Ffrr-pythontools_10.3-sonic-0_all.deb

FROM ghcr.io/metal-stack/mini-lab-sonic-container-base:202505

ARG FRR_RELOAD_URL
ADD "${FRR_RELOAD_URL}" /tmp/frr-pythontools.deb

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install --yes --no-install-recommends \
        dbus \
        docker.io \
        ethtool \
        fuse-overlayfs \
        iptables \
        jq \
        lldpd \
        systemd \
        systemd-sysv \
    && dpkg -i /tmp/frr-pythontools.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/frr-pythontools.deb

# same port naming as the VM flavor (single-lane Ethernet0..Ethernet119 plus
# Ethernet120/124), so the existing inventory (spine uplink Ethernet120) applies
ARG HWSKU_DIR=/usr/share/sonic/device/x86_64-kvm_x86_64-r0/Accton-AS7726-32X
COPY port_config.ini lanemap.ini ${HWSKU_DIR}/

# start.sh only brings up the FRR daemons that SONiC needs unconditionally.
# bgpd is left to the per-vendor bgp container which does not exist here
RUN sed -i '/supervisorctl start staticd/a\\nsupervisorctl start bgpd\n\n[ -f /etc/frr/frr.conf ] \&\& vtysh -b || true' /usr/bin/start.sh

COPY frr-reload /usr/lib/frr/frr-reload
COPY sonic-init.sh healthcheck.sh /usr/local/bin/
COPY daemon.json /etc/docker/daemon.json
COPY lldpd.conf /etc/lldpd.d/mini-lab.conf
COPY systemd/ /etc/systemd/system/

# sonic-configdb-utils and parts of the SONiC CLI read platform information
# from this file. On the VM flavor it is written by launch.py
RUN printf 'SONIC_VERSION=202505\nPLATFORM=x86_64-kvm_x86_64-r0\nHWSKU=Accton-AS7726-32X\nDEVICE_TYPE=LeafRouter\nASIC_TYPE=vs\n' >/etc/sonic/sonic-environment

# metal-core and the sonic-config role manage the FRR config in /etc/sonic/frr,
# which on SONiC is bind-mounted into the bgp container as /etc/frr.
# FRR runs directly here, so both paths must point to the same files
RUN mkdir -p /etc/sonic/frr \
    && mv /etc/frr/* /etc/sonic/frr/ \
    && rmdir /etc/frr \
    && ln -s /etc/sonic/frr /etc/frr

RUN chmod +x /usr/lib/frr/frr-reload /usr/local/bin/sonic-init.sh /usr/local/bin/healthcheck.sh \
    && systemctl enable ssh docker lldpd sonic-init.service sonic.service sonic.target \
        database.service bgp.service swss.service syncd.service \
# mask units that collide with supervisord-managed services. These are services that are pulled in
# from the debian base image and previously inert SONiC services, that were enabled by pulling in systemd as PID 1
    && systemctl mask getty@tty1.service console-getty.service \
        redis-server.service rsyslog.service frr.service networking.service \
        caclmgrd.service procdockerstatsd.service \
        determine-reboot-cause.service process-reboot-cause.service \
        aaastatsd.timer featured.timer hostcfgd.timer \
    && mkdir -p /root/.ssh && chmod 700 /root/.ssh

HEALTHCHECK --start-period=60s --interval=5s --retries=60 CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/sbin/init"]
