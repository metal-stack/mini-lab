#!/usr/bin/env bash
set -eo pipefail

for i in "$@"
do
case $i in
    -c=*|--client-pem=*)
    CLIENT_PEM="${i#*=}"
    shift
    ;;
    -C=*|--client-key=*)
    CLIENT_KEY="${i#*=}"
    shift
    ;;
    -s=*|--server-pem=*)
    SERVER_PEM="${i#*=}"
    shift
    ;;
    -S=*|--server-key=*)
    SERVER_KEY="${i#*=}"
    shift
    ;;
    -h=*|--host=*)
    HOST="${i#*=}"
    shift
    ;;
    *)
    echo "unknown parameter passed: $1"
    exit 1
    ;;
esac
done

if [ -z "$CLIENT_PEM" ]; then
      echo "--client-pem is a required parameter";
      exit 1
fi
if [ -z "$CLIENT_KEY" ]; then
      echo "--client-key is a required parameter";
      exit 1
fi
if [ -z "$SERVER_PEM" ]; then
      echo "--server-pem is a required parameter";
      exit 1
fi
if [ -z "$SERVER_KEY" ]; then
      echo "--server-key is a required parameter";
      exit 1
fi
if [ -z "$HOST" ]; then
      echo "--host is a required parameter";
      exit 1
fi

chmod 0600 *-key.pem

openssl s_server -cert ${SERVER_PEM} -key ${SERVER_KEY} -WWW -port 12345 -CAfile ../ca.pem -verify_return_error &

trap "kill $(ps aux | grep openssl | grep s_server | grep WWW | grep 12345 | tail -1 | awk '{print $2}')" EXIT

diff <(curl --cert ${CLIENT_PEM} --key ${CLIENT_KEY} --cacert ../ca.pem --header "Host: ${HOST}" --resolve ${HOST}:12345:127.0.0.1 https://${HOST}:12345/${SERVER_PEM}) ${SERVER_PEM}
