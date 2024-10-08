#!/bin/bash

########
# Builds the multiarch docker image and pushes it to the docker registry
########

set -exu
set -o pipefail

# Load our common environment variables for publishing
export CURDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
source $CURDIR/publish-common.sh

# Set our tag name as well as the tag names of the indiividual platform images
TAG_NAME="${BASE_TAG_NAME}:${DOCKER_TAG_VERSION}"
AMD64_TAG="${BASE_TAG_NAME}:${DOCKER_TAG_VERSION}-amd64"
ARM64_TAG="${BASE_TAG_NAME}:${DOCKER_TAG_VERSION}-arm64"

# Pull the images from the registry
buildah pull $AMD64_TAG
buildah pull $ARM64_TAG

# ensure +x is set to avoid writing any sensitive information to the console
set +x

DOCKER_PASSWORD=$(vault read -address "${VAULT_ADDR}" -field secret_20230609 secret/ci/elastic-connectors/${VAULT_USER})

# Log into Docker
echo "Logging into docker..."
DOCKER_USER=$(vault read -address "${VAULT_ADDR}" -field user_20230609 secret/ci/elastic-connectors/${VAULT_USER})
vault read -address "${VAULT_ADDR}" -field secret_20230609 secret/ci/elastic-connectors/${VAULT_USER} | \
  buildah login --username="${DOCKER_USER}" --password-stdin docker.elastic.co

# Create the manifest for the multiarch image
echo "Creating manifest..."
buildah manifest create $TAG_NAME \
  $AMD64_TAG \
  $ARM64_TAG

# ... and push it
echo "Pushing manifest..."
buildah manifest push $TAG_NAME docker://$TAG_NAME

# Write out the final manifest for debugging purposes
echo "Built and pushed multiarch image... dumping final manifest..."
buildah manifest inspect $TAG_NAME
