# Based on python:3.10.14-alpine3.20
FROM ghcr.io/netcracker/qubership-docker-integration-tests:0.2.2

# User with UID=1000 already added in ghcr.io/netcracker/qubership-docker-integration-tests image
ENV USER_UID=1000 \
    ROBOT_OUTPUT=/opt/robot/output \
    SERVICE_CHECKER_SCRIPT=${ROBOT_HOME}/jaeger_pods_checker.py

# Copy tests source code
COPY requirements.txt ${ROBOT_HOME}/requirements.txt
COPY robot ${ROBOT_HOME}

RUN \
    # Install requirements
    python3 -m pip install --no-cache-dir \
        -r "${ROBOT_HOME}/requirements.txt" \
    # Cleanup pip cache
    && rm -rf /var/cache/apk/* \
    # Create output directory for test results
    && mkdir -p "${ROBOT_OUTPUT}"

USER ${USER_UID}

EXPOSE 8080
VOLUME ["${ROBOT_OUTPUT}"]
