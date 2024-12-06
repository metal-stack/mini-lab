FROM docker.io/library/debian:bookworm-backports

ENV LIBGUESTFS_BACKEND=direct

RUN apt-get update && \
    apt-get --no-install-recommends install --yes \
        curl \
        iproute2 \
        linux-image-cloud-amd64 \
        python3 \
        python3-guestfs \
        qemu-system-x86 \
        telnet

COPY --from=ghcr.io/metal-stack/mini-lab-sonic:base /sonic-vs.img /sonic-vs.img
COPY --from=ghcr.io/metal-stack/mini-lab-sonic:base /frr-pythontools.deb /frr-pythontools.deb

ENTRYPOINT ["/launch.py"]

COPY mirror_tap_to_eth.sh mirror_tap_to_front_panel.sh port_config.ini launch.py /
