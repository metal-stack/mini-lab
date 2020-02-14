FROM python:buster

ENV VERSION_VAGRANT=2.2.7 \
    VERSION_HELM=3.0.3 \
    VERSION_ANSIBLE=2.9.2 \
    VERSION_STERN=1.11.0 \
    ANSIBLE_CONFIG=/mini-lab/ansible.cfg \
    ANSIBLE_VAGRANT_USE_CACHE=1 \
    ANSIBLE_VAGRANT_CACHE_MAX_AGE=36000

# vagrant is required for running the vagrant dynamic inventory script from within the container...
ARG VAGRANT_PACKAGE_URL=https://releases.hashicorp.com/vagrant/${VERSION_VAGRANT}/vagrant_${VERSION_VAGRANT}_x86_64.deb

RUN set -x \
 && apt-get update \
 && apt-get install --yes --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg2 \
        software-properties-common \
        connect-proxy \
        libvirt-dev \
        ruby-dev \
        rsync \
 && curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add - \
 && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian buster stable" \
 && apt-get update \
 && apt-get install --yes --no-install-recommends docker-ce  \
 && curl -fsSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash -s -- --version "v${VERSION_HELM}" \
 && pip install --upgrade pip \
 && pip install ansible==${VERSION_ANSIBLE} netaddr humanfriendly openshift \
 && curl -fo vagrant.deb $VAGRANT_PACKAGE_URL \
 && dpkg -i vagrant.deb \
 && rm -f vagrant.deb \
 && vagrant plugin install vagrant-libvirt \
 && curl -Lo stern https://github.com/wercker/stern/releases/download/${VERSION_STERN}/stern_linux_amd64 \
 && chmod +x stern \
 && mv stern /usr/bin/

COPY --from=registry.fi-ts.io/metal/metalctl /metalctl /
