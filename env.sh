#!/usr/bin/env bash
set -eo pipefail
set -e

echo "Obtaining release vector variables..."

yq_shell() {
  docker run --rm -i -v ${PWD}:/workdir mikefarah/yq:3 /bin/sh -c "$@"
}

download_oci_release_vector() {
  local image="$1"
  local tag="$2"

  local token=$(curl -s "https://ghcr.io/token?scope=repository:$image:pull&service=ghcr.io" | jq -r .token)

  local manifest=$(curl -s -L -H "Accept: application/vnd.oci.image.manifest.v1+json" -H "Authorization: Bearer $token" https://ghcr.io/v2/$image/manifests/$tag)
  local digest=$(echo "$manifest" | jq -r '.layers[] | select(.mediaType == "application/vnd.metal-stack.release-vector.v1.tar+gzip") | .digest')

  RELEASE_YAML="$(curl -s -L -H "Authorization: Bearer $token" "https://ghcr.io/v2/$image/blobs/$digest" | tar xzO release.yaml)"
}

METAL_STACK_RELEASE_VERSION=$(yq_shell "yq r inventories/group_vars/all/release_vector.yaml 'metal_stack_release_version'")
download_oci_release_vector metal-stack/releases $METAL_STACK_RELEASE_VERSION

METALCTL_IMAGE_TAG=$(yq_shell "echo \"${RELEASE_YAML}\" | yq r - docker-images.metal-stack.control-plane.metalctl.tag")
DEPLOYMENT_BASE_IMAGE_TAG=$(yq_shell "echo \"${RELEASE_YAML}\" | yq r - docker-images.metal-stack.generic.deployment-base.tag")

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
KIND_EXPERIMENTAL_DOCKER_NETWORK=${MINI_LAB_INTERNAL_NETWORK:=mini_lab_internal}

METALCTL_HMAC=${METALCTL_HMAC:=metal-admin}
METALCTL_API_URL=${METALCTL_API_URL:=https://api.172.42.0.42.nip.io/metal}
METALCTL_CERTIFICATE_AUTHORITY_DATA=${METALCTL_CERTIFICATE_AUTHORITY_DATA:=$(cat files/certs/ca.pem | base64 -w0)}

METAL_APIV2_URL=${METAL_APIV2_URL:=http://v2.172.42.0.42.nip.io}
EOF
