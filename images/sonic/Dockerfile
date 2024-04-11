FROM ubuntu:22.04

ENV LIBGUESTFS_BACKEND=direct

RUN apt-get update && \
    apt-get --no-install-recommends install --yes \
        linux-image-5.15.0-102-generic \
        net-tools \
        ovmf \
        python3 \
        python3-guestfs \
        qemu-system-x86 \
        telnet \
        tini

ENTRYPOINT ["/usr/bin/tini", "--"]

COPY config_db.json mirror_tap_to_eth.sh sonic_entrypoint.py /

CMD ["/usr/bin/python3", "-u", "/sonic_entrypoint.py"]
