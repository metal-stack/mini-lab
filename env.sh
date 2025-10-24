#!/usr/bin/env bash

set -e

echo "Obtaining release vector variables..."

yq_shell() {
  docker run --rm -i -v ${PWD}:/workdir mikefarah/yq:3 /bin/sh -c "$@"
}

METAL_STACK_RELEASE_VERSION=$(yq_shell "yq r inventories/group_vars/all/images.yaml 'metal_stack_release_version'")
RELEASE_YAML=$(curl -s https://raw.githubusercontent.com/metal-stack/releases/${METAL_STACK_RELEASE_VERSION}/release.yaml)
METALCTL_IMAGE_TAG=$(yq_shell "echo \"${RELEASE_YAML}\" | yq r - docker-images.metal-stack.control-plane.metalctl.tag")
DEPLOYMENT_BASE_IMAGE_TAG=sshpass-minimal

echo "{}" > .extra_vars.yaml
if [ ! -z ${ANSIBLE_EXTRA_VARS_FILE} ]; then
  cat ${ANSIBLE_EXTRA_VARS_FILE} > .extra_vars.yaml || echo "{}" > .extra_vars.yaml
fi

cat << EOF > .env
METALCTL_IMAGE_TAG=${METALCTL_IMAGE_TAG}
DEPLOYMENT_BASE_IMAGE_TAG=${DEPLOYMENT_BASE_IMAGE_TAG}
CI=${CI:=false}
DOCKER_HUB_USER=${DOCKER_HUB_USER:=}
DOCKER_HUB_TOKEN=${DOCKER_HUB_TOKEN:=}
EOF
