# Based on python:3.13.3-alpine3.21
FROM ghcr.io/netcracker/qubership-docker-integration-tests:feature-remove-openshift-lib-usage

# User with UID=1000 already added in ghcr.io/netcracker/qubership-docker-integration-tests image
ENV ROBOT_OUTPUT=/opt/robot/output \
    SERVICE_CHECKER_SCRIPT=${ROBOT_HOME}/jaeger_pods_checker.py

# Copy tests source code
COPY robot/* ${ROBOT_HOME}/

# Create output directory for test results
RUN mkdir -p "${ROBOT_OUTPUT}"

VOLUME ["${ROBOT_OUTPUT}"]
