ARG SONIC_BASE_URL=https://sonic-build.azurewebsites.net/api/sonic/artifacts?branchName=202311&platform=vs
ARG FRR_RELOAD_URL=${SONIC_BASE_URL}&target=target%2Fdebs%2Fbullseye%2Ffrr-pythontools_8.5.1-sonic-0_all.deb

FROM docker.io/library/busybox:stable AS download

ARG FRR_RELOAD_URL

ADD "${FRR_RELOAD_URL}" /frr-pythontools.deb

COPY sonic-vs.img.gz .
RUN gunzip sonic-vs.img.gz

FROM scratch

ARG FRR_RELOAD_URL

LABEL frr-reload-url=${FRR_RELOAD_URL}

COPY --from=download /frr-pythontools.deb /frr-pythontools.deb
COPY --from=download /sonic-vs.img /sonic-vs.img
