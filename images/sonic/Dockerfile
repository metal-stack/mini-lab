FROM docker.io/library/debian:bookworm-backports

ENV LIBGUESTFS_BACKEND=direct

RUN apt-get update && \
    apt-get --no-install-recommends install --yes \
        curl \
        libpcap0.8 \
        iproute2 \
        linux-image-cloud-amd64 \
        python3 \
        python3-guestfs \
        python3-scapy \
        qemu-system-x86 \
        telnet

COPY --from=ghcr.io/metal-stack/mini-lab-sonic-base:202505 /sonic-vs.img /sonic-vs.img
COPY --from=ghcr.io/metal-stack/mini-lab-sonic-base:202505 /frr-pythontools.deb /frr-pythontools.deb

ENTRYPOINT ["/launch.py"]

COPY mirror_tap_to_eth.sh mirror_tap_to_front_panel.sh port_config.ini launch.py /

# Readiness now waits for the dataplane (front-panel LLDP), which converges later than the
# mgmt plane, so allow more time before the container is considered unhealthy.
HEALTHCHECK --start-period=30s --interval=5s --retries=40 CMD test -f /healthy
