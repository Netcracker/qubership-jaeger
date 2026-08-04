# Build and registry notes — Go delta

Shared blocker handling, smoke-vs-validation rule, and the provenance table:
[`opentelemetry-tracing-common/reference/build-preconditions.md`](../../opentelemetry-tracing-common/reference/build-preconditions.md).

Go specifics below.

## Build check

The post-L4 build check is `go build ./...` and `go test ./...` (or the
install-doc equivalent), followed by a container image with a session-unique tag —
[`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md). Purge
`bin/`, `dist/`, and module-specific output directories before it runs.

Write the command into `buildProvenance.buildCommand`, the compiled binary into
`runnerArtifact`.

## Private module registries

Go services often resolve modules from private sources (GitHub Packages, internal
mirrors, `GOPRIVATE`/`GONOSUMDB` entries). Record the blocker as
`build blocked: private-registry — <module path>`; the handling is the shared one.

## Provenance evidence

When a pre-built image is reused, compare its build metadata against the current
`go.mod` and the L4 diff before accepting `ci-image`.
