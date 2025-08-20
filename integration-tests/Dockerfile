# Based on python:3.13-alpine3.22
# checkov:skip=CKV_DOCKER_3: User already set in the base image
FROM ghcr.io/netcracker/qubership-docker-integration-tests:0.3.2

# Env ${ROBOT_HOME} is set in the base image as /opt/robot
ENV SERVICE_CHECKER_SCRIPT=${ROBOT_HOME}/jaeger_pods_checker.py

# Copy tests source code
COPY requirements.txt ${ROBOT_HOME}/requirements.txt
COPY robot ${ROBOT_HOME}

RUN \
    # Install requirements
    python3 -m pip install --no-cache-dir \
        -r "${ROBOT_HOME}/requirements.txt" \
    && apk add --no-cache curl \
    # Cleanup pip cache
    && rm -rf /var/cache/apk/* \
    # Create output directory for test results
    && mkdir -p "${ROBOT_OUTPUT}"

USER ${USER_UID}

EXPOSE 8080
VOLUME ["${ROBOT_OUTPUT}"]
