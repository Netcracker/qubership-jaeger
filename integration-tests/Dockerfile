# Based on python:3.13-alpine3.22
# checkov:skip=CKV_DOCKER_3: User already set in the base image
FROM ghcr.io/netcracker/qubership-docker-integration-tests:0.6.2@sha256:6037b2af4643cea6f31b539d545a67744fa2b6c4b157ec5cf20fa438b86e75f6

# Env ${ROBOT_HOME} is set in the base image as /opt/robot
ENV SERVICE_CHECKER_SCRIPT=${ROBOT_HOME}/jaeger_pods_checker.py

# Install tracegen for reliable load generation
# Copy binary from official jaeger-tracegen Docker image (located at /go/bin/tracegen-linux)
COPY --from=jaegertracing/jaeger-tracegen:2.21.0@sha256:fef7c1ffb6d2c0977413ac99f85eaf650eb97278f0f9566e1b0ff6275d697428 /go/bin/tracegen-linux /usr/local/bin/tracegen
RUN chmod +x /usr/local/bin/tracegen

# Copy tests source code
COPY robot/ ${ROBOT_HOME}/

USER 1000
