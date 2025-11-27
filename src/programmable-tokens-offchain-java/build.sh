#!/usr/bin/env bash

set -x

VERSION=$(git describe --tags --always --dirty)

echo "Building version: ${VERSION}"

./gradlew bootJar

DOCKER_IMAGE_NAME=easy1staking/programmable-tokens-indexer
DOCKER_IMAGE="${DOCKER_IMAGE_NAME}:${VERSION}"
DOCKER_IMAGE_LATEST="${DOCKER_IMAGE_NAME}:latest"

docker build -t "${DOCKER_IMAGE}" -t "${DOCKER_IMAGE_LATEST}" --push .
