#!/usr/bin/env bash
set -eo pipefail

cd /work/files/certs

rm -f *.pem
rm -f **/*.pem
rm -f **/*.crt

echo "generating ca cert"
cfssl genkey -initca ca-csr.json | cfssljson -bare ca
rm *.csr

for component in \
        grpc \
        masterdata-api; do
    pushd $component

    echo "generating $component certs"

    if [ -f "server.json" ]; then
        cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client-server server.json | cfssljson -bare server
    fi

    if [ -f "client.json" ]; then
        cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client client.json | cfssljson -bare client
    fi

    rm *.csr

    popd
done

# TODO: fix nsq using concatenated certs
pushd nsq
cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client-server client.json | cfssljson -bare client
cat client.pem client-key.pem > client.crt
rm -f *.csr
popd
