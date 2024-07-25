FROM debian:bookworm-slim

ENV LIBGUESTFS_BACKEND=direct
# Check: https://sonic-build.azurewebsites.net/ui/sonic/pipelines
ARG SONIC_BASE_URL=https://sonic-build.azurewebsites.net/api/sonic/artifacts?branchName=202311&platform=vs
ARG SONIC_IMG_URL=${SONIC_BASE_URL}&target=target%2Fsonic-vs.img.gz
ARG FRR_RELOAD_URL=${SONIC_BASE_URL}&target=target%2Fdebs%2Fbullseye%2Ffrr-pythontools_8.5.1-sonic-0_all.deb

RUN apt-get update && \
    apt-get --no-install-recommends install --yes \
        curl \
        linux-image-cloud-amd64 \
        net-tools \
        python3 \
        python3-guestfs \
        qemu-system-x86 \
        telnet

RUN curl --location --output - "${SONIC_IMG_URL}" | gunzip > sonic-vs.img && \
    curl --location --output /frr-pythontools.deb "${FRR_RELOAD_URL}"

ENTRYPOINT ["/launch.py"]

COPY config_db.json mirror_tap_to_eth.sh launch.py /
