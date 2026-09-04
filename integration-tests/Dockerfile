# Based on python:3.13-alpine3.22
# checkov:skip=CKV_DOCKER_3: User already set in the base image
FROM ghcr.io/netcracker/qubership-docker-integration-tests:0.5.8@sha256:011dcece3e8a624c99983456f401e3080e71ad6faf82fe89bd27a0591f00d4bd

# Env ${ROBOT_HOME} is set in the base image as /opt/robot
ENV SERVICE_CHECKER_SCRIPT=${ROBOT_HOME}/jaeger_pods_checker.py

# Install tracegen for reliable load generation
# Copy binary from official jaeger-tracegen Docker image (located at /go/bin/tracegen-linux)
COPY --from=jaegertracing/jaeger-tracegen:2.20.0@sha256:be38b7a33c51ff4835708319abbdb284e1ff34e5fde2d047fc453e7c01d0708b /go/bin/tracegen-linux /usr/local/bin/tracegen
RUN chmod +x /usr/local/bin/tracegen

# Copy tests source code
COPY robot/ ${ROBOT_HOME}/

USER 1000
