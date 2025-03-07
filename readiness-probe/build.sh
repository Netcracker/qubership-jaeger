#!/bin/bash
set -e

ARTIFACT_NAME="readiness-probe"

cd "$(dirname "$0")"

docker build -t ${ARTIFACT_NAME} ./

for id in ${DOCKER_NAMES}; do
    docker tag ${ARTIFACT_NAME} "$id"
done
