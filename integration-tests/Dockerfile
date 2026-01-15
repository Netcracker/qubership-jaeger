# Based on python:3.13-alpine3.22
# checkov:skip=CKV_DOCKER_3: User already set in the base image
FROM ghcr.io/netcracker/qubership-docker-integration-tests:0.3.6

# Env ${ROBOT_HOME} is set in the base image as /opt/robot
ENV SERVICE_CHECKER_SCRIPT=${ROBOT_HOME}/jaeger_pods_checker.py

# Install tracegen for reliable load generation
# Copy binary from official jaeger-tracegen Docker image (located at /go/bin/tracegen-linux)
COPY --from=jaegertracing/jaeger-tracegen:latest /go/bin/tracegen-linux /usr/local/bin/tracegen
RUN chmod +x /usr/local/bin/tracegen

# Copy tests source code
COPY robot/ ${ROBOT_HOME}/
