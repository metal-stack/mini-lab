FROM docker.io/library/debian:bookworm-slim

ENV LIBGUESTFS_BACKEND=direct

RUN apt-get update && \
    apt-get --no-install-recommends install --yes \
        curl \
        linux-image-cloud-amd64 \
        net-tools \
        python3 \
        python3-guestfs \
        qemu-system-x86 \
        telnet

COPY --from=ghcr.io/metal-stack/mini-lab-sonic:base /sonic-vs.img /sonic-vs.img
COPY --from=ghcr.io/metal-stack/mini-lab-sonic:base /frr-pythontools.deb /frr-pythontools.deb

ENTRYPOINT ["/launch.py"]

COPY config_db.json mirror_tap_to_eth.sh launch.py /
