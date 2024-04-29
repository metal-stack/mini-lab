FROM ubuntu:22.04

ENV LIBGUESTFS_BACKEND=direct
# Check: https://sonic-build.azurewebsites.net/ui/sonic/pipelines
ENV SONIC_REMOTE_IMG=https://sonic-build.azurewebsites.net/api/sonic/artifacts?branchName=202211&platform=vs&target=target%2Fsonic-vs.img.gz

RUN apt-get update && \
    apt-get --no-install-recommends install --yes \
        curl \
        linux-image-5.15.0-102-generic \
        net-tools \
        ovmf \
        python3 \
        python3-guestfs \
        qemu-system-x86 \
        telnet \
        tini && \
    curl --location --output - "${SONIC_REMOTE_IMG}" | gunzip > sonic-vs.img

ENTRYPOINT ["/usr/bin/tini", "--"]

COPY config_db.json mirror_tap_to_eth.sh sonic_entrypoint.py /

CMD ["/usr/bin/python3", "-u", "/sonic_entrypoint.py"]
