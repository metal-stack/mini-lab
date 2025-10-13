# Check: https://sonic-build.azurewebsites.net/ui/sonic/pipelines
ARG SONIC_BASE_URL=https://sonic-build.azurewebsites.net/api/sonic/artifacts?branchName=202311&platform=vs
ARG SONIC_IMG_URL=${SONIC_BASE_URL}&target=target%2Fsonic-vs.img.gz
ARG FRR_RELOAD_URL=${SONIC_BASE_URL}&target=target%2Fdebs%2Fbullseye%2Ffrr-pythontools_8.5.1-sonic-0_all.deb

FROM docker.io/library/busybox:stable AS download

ARG SONIC_IMG_URL
ARG FRR_RELOAD_URL

ADD "${SONIC_IMG_URL}" /sonic-vs.img.gz
ADD "${FRR_RELOAD_URL}" /frr-pythontools.deb

RUN gunzip /sonic-vs.img.gz

FROM scratch

ARG SONIC_IMG_URL
ARG FRR_RELOAD_URL

LABEL sonic-img-url=${SONIC_IMG_URL} \
      frr-reload-url=${FRR_RELOAD_URL}

COPY --from=download /frr-pythontools.deb /frr-pythontools.deb
COPY --from=download /sonic-vs.img /sonic-vs.img
