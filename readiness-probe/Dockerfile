# Build the manager binary
# Note: this uses the host platform for the build, and we ask go build to target the needed platform, so we do not spend time on qemu emulation when running "go build"
FROM --platform=$BUILDPLATFORM golang:1.26.4-alpine3.22@sha256:727cfc3c40be55cd1bc9a4a059406b28a059857e3be752aa9d09531e12c20c56 AS builder
ARG BUILDPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG GOPROXY=""
ENV GO111MODULE=on

WORKDIR /workspace

COPY go.mod go.mod
COPY go.sum go.sum

# cache deps before building and copying source so that we don't need to re-download as much
# and so that source changes don't invalidate our downloaded layer
RUN go mod download -x

# Copy the go source
COPY main.go main.go

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -a -o probe .

# Main container
FROM alpine:3.24.1@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

ENV USER_UID=2001 \
    USER_NAME=probe \
    GROUP_NAME=probe

WORKDIR /app/

COPY --from=builder --chown=${USER_UID} /workspace/probe /app/

RUN addgroup ${GROUP_NAME} \
    && adduser -D -G ${GROUP_NAME} -u ${USER_UID} ${USER_NAME}

USER ${USER_UID}

CMD ["/app/probe"]
