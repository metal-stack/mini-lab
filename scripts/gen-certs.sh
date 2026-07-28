#!/usr/bin/env bash

# Generates the mini-lab TLS certificates by running the cfssl container, which
# in turn executes scripts/roll_certs.sh inside it. All output goes to stderr so
# this can be called safely from $(shell ...) / recipes that capture stdout.

set -eo pipefail

# resolve the repo root (parent of this script's dir) so we work from any cwd
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "certificate generation required, running cfssl container" >&2

docker run --rm \
	--user "$(id -u):$(id -g)" \
	--entrypoint bash \
	-v "${repo_root}:/work" \
	cfssl/cfssl /work/scripts/roll_certs.sh 1>&2
