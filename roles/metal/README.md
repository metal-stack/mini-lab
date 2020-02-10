# metal

This role contains a [helm chart](control-plane/roles/metal/files/metal-control-plane) that contains all components (except for the rethinkdb) of a metal control plane.

The helm chart is being parametrized with helm value files that are located in the `templates` folder. So we have Ansible's Jinja2 templating for the helm value files and helm's "go-template" rendering when deploying the chart.

The helm chart uses [hooks](https://github.com/helm/helm/blob/master/docs/charts_hooks.md) to deploy the control plane. There is a post-install hook to initialize the rethinkdb (as there would be race conditions when there are multiple metal-apis). Then there are post-install and post-upgrade hooks to initialize and update the "masterdata" of the control plane (like images, partitions, networks in this control plane).

As our control plane also requires non-HTTP ports to be exposed to the outside world, we currently use [tcp and udp service exposal of Kubernetes nginx-ingress](https://kubernetes.github.io/ingress-nginx/user-guide/exposing-tcp-udp-services/).

### How to create the certs for NSQ

```shell script
#!/usr/bin/env bash
set -eo pipefail

cd control-plane/roles/metal/files/certs/nsq

pushd prod
cfssl genkey -initca csr.json | cfssljson -bare ca_cert
cfssl gencert -ca ca_cert.pem -ca-key ca_cert-key.pem csr.json | cfssljson -bare client_cert
cat client_cert.pem client_cert-key.pem > client.pem
rm -f *.csr
popd

pushd test
cfssl genkey -initca csr.json | cfssljson -bare ca_cert
cfssl gencert -ca ca_cert.pem -ca-key ca_cert-key.pem csr.json | cfssljson -bare client_cert
cat client_cert.pem client_cert-key.pem > client.pem
rm -f *.csr
popd

pushd vagrant
cfssl genkey -initca csr.json | cfssljson -bare ca_cert
cfssl gencert -ca ca_cert.pem -ca-key ca_cert-key.pem csr.json | cfssljson -bare client_cert
cat client_cert.pem client_cert-key.pem > client.pem
rm -f *.csr
popd
```
