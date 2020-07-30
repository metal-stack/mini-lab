#!/usr/bin/env bash

set -e

yq_shell() {
  docker run --rm -i -v ${PWD}:/workdir mikefarah/yq /bin/sh -c "$@"
}

METAL_STACK_RELEASE_VERSION=$(yq_shell "yq r group_vars/all/images.yaml 'metal_stack_release_version'")
RELEASE_YAML=$(curl -s https://raw.githubusercontent.com/metal-stack/releases/${METAL_STACK_RELEASE_VERSION}/release.yaml)
METALCTL_IMAGE_TAG=$(yq_shell "echo \"${RELEASE_YAML}\" | yq r - docker-images.metal-stack.control-plane.metalctl.tag")

cat << EOF > .env
METALCTL_IMAGE_TAG=${METALCTL_IMAGE_TAG}
EOF