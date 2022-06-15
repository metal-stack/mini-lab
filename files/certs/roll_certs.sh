#!/usr/bin/env bash
set -eo pipefail

for i in "$@"
do
case $i in
    -v=*|--vault-password-file=*)
    VAULT_PASSWORD_FILE="${i#*=}"
    shift
    ;;
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
    ../test_certs.sh --client-pem=client.pem --client-key=client-key.pem --server-pem=server.pem --server-key=server-key.pem --host=metal-api-grpc
    popd
fi

if [ -z "$TARGET" ] || [ $TARGET == "masterdata-api" ]; then
    pushd masterdata-api
    echo "generating masterdata-api certs"
    rm -f *.pem
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client-server server.json | cfssljson -bare server
    cfssl gencert -ca=../ca.pem -ca-key=../ca-key.pem -config=../ca-config.json -profile=client client.json | cfssljson -bare client
    rm *.csr
    ../test_certs.sh --client-pem=client.pem --client-key=client-key.pem --server-pem=server.pem --server-key=server-key.pem --host=masterdata-api
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

if [ -n "$VAULT_PASSWORD_FILE" ]; then
    if [ -z "$TARGET" ]; then
        TARGET="*"
    fi
    ansible-vault encrypt --vault-password-file "${VAULT_PASSWORD_FILE}" $TARGET/*.pem
    ansible-vault encrypt --vault-password-file "${VAULT_PASSWORD_FILE}" $TARGET/*.crt >/dev/null 2>&1 || true
fi
