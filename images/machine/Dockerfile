FROM docker.io/library/debian:bookworm-backports

ENV QEMU_DISK_SIZE=5G

RUN apt-get update && \
    apt-get --no-install-recommends install --yes \
        ipmitool \
        iproute2 \
        openipmi \
        procps \
        python3 \
        qemu-utils \
        qemu-system-x86 \
        telnet

COPY --from=ghcr.io/metal-stack/mini-lab-ovmf:edk2-stable202408.01 /OVMF_*.fd /opt/OVMF/

COPY . /

ENTRYPOINT ["/entrypoint.sh"]
