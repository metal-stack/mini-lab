#!/usr/bin/env bash
set -eo pipefail

cd /work/files/certs

for i in "$@"
do
case $i in
    -t=*|--target=*)
    TARGET="${i#*=}"
    shift
    ;;
    *)
    echo "unknown parameter passed: $1"
    exit 1
    ;;
esac
done

if [ -z "$TARGET" ]; then
    echo "generating ca cert"
    cfssl genkey -initca ca-csr.json | cfssljson -bare ca
    rm *.csr
fi

if [ -z "$TARGET" ] || [ $TARGET == "grpc" ]; then
    pushd grpc
    echo "generating grpc certs"
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=server server.json | cfssljson -bare server
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client client.json | cfssljson -bare client
    rm *.csr
    popd
fi

if [ -z "$TARGET" ] || [ $TARGET == "masterdata-api" ]; then
    pushd masterdata-api
    echo "generating masterdata-api certs"
    rm -f *.pem
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client-server server.json | cfssljson -bare server
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client client.json | cfssljson -bare client
    rm *.csr
    popd
fi

if [ -z "$TARGET" ] || [ $TARGET == "nsq" ]; then
    pushd nsq
    rm -f *.pem
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client-server client.json | cfssljson -bare client
    cat client.pem client-key.pem > client.crt
    rm -f *.csr
    popd
fi


if [ -z "$TARGET" ] || [ $TARGET == "gardener-admission-controller" ]; then
    pushd gardener-admission-controller
    rm -f *.pem
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=server server.json | cfssljson -bare server
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client client.json | cfssljson -bare client
    rm *.csr
    popd
fi

if [ -z "$TARGET" ] || [ $TARGET == "gardener-apiserver" ]; then
    pushd gardener-apiserver
    rm -f *.pem
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=server server.json | cfssljson -bare server
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client client.json | cfssljson -bare client
    rm *.csr
    popd
fi

if [ -z "$TARGET" ] || [ $TARGET == "gardener-controller-manager" ]; then
    pushd gardener-controller-manager
    rm -f *.pem
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=server server.json | cfssljson -bare server
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client client.json | cfssljson -bare client
    rm *.csr
    popd
fi

if [ -z "$TARGET" ] || [ $TARGET == "gardener-etcd" ]; then
    pushd gardener-etcd
    rm -f *.pem
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client-server server.json | cfssljson -bare server
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client client.json | cfssljson -bare client
    rm *.csr
    popd
fi

if [ -z "$TARGET" ] || [ $TARGET == "gardener-kube-aggregator" ]; then
    pushd gardener-kube-aggregator
    rm -f *.pem
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client client.json | cfssljson -bare client
    rm *.csr
    popd
fi

if [ -z "$TARGET" ] || [ $TARGET == "metal-admission-controller" ]; then
    pushd metal-admission-controller
    rm -f *.pem
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=server server.json | cfssljson -bare server
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client client.json | cfssljson -bare client
    rm *.csr
    popd
fi

if [ -z "$TARGET" ] || [ $TARGET == "virtual-kube-apiserver" ]; then
    pushd virtual-kube-apiserver
    rm -f *.pem
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=server server.json | cfssljson -bare server
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client kube-controller-manager-client.json | cfssljson -bare client
    mv client-key.pem kube-controller-manager-client-key.pem
    mv client.pem kube-controller-manager-client.pem
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client admin-client.json | cfssljson -bare client
    mv client-key.pem admin-client-key.pem
    mv client.pem admin-client.pem
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client gardener-apiserver-client.json | cfssljson -bare client
    mv client-key.pem gardener-apiserver-client-key.pem
    mv client.pem gardener-apiserver-client.pem
    rm *.csr
    popd
fi

if [ -z "$TARGET" ] || [ $TARGET == "virtual-service-account-token" ]; then
    pushd virtual-service-account-token
    rm -f *.pem
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client client.json | cfssljson -bare client
    rm *.csr
    popd
fi
