# Based on python:3.13-alpine3.22
# checkov:skip=CKV_DOCKER_3: User already set in the base image
FROM ghcr.io/netcracker/qubership-docker-integration-tests:0.5.4@sha256:343b6be9cf2a116c42f7afa1a58670e7a2f08706527546c9c4944a7cb12be54e

# Env ${ROBOT_HOME} is set in the base image as /opt/robot
ENV SERVICE_CHECKER_SCRIPT=${ROBOT_HOME}/jaeger_pods_checker.py

# Install tracegen for reliable load generation
# Copy binary from official jaeger-tracegen Docker image (located at /go/bin/tracegen-linux)
COPY --from=jaegertracing/jaeger-tracegen:2.18.0@sha256:96e94561b4cf76e87fc114f2a94b409d762c3db0966dc2f71e5fb9a2022fe6ce /go/bin/tracegen-linux /usr/local/bin/tracegen
RUN chmod +x /usr/local/bin/tracegen

# Copy tests source code
COPY robot/ ${ROBOT_HOME}/
