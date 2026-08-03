# Build and registry notes — Java delta

Shared blocker handling, smoke-vs-validation rule, and the provenance table:
[`opentelemetry-tracing-common/reference/build-preconditions.md`](../../opentelemetry-tracing-common/reference/build-preconditions.md).

Java specifics below.

## Build check

The post-L4 build check is `mvn clean package` (or the Gradle equivalent from the
install docs), followed by a container image with a session-unique tag —
[`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md). Purge
`target/` before it runs.

Write the command into `buildProvenance.buildCommand`, the runner JAR path into
`runnerArtifact`.

## Private Maven registries

Many Qubership/NC Java services declare `<repositories>` pointing at
`maven.pkg.github.com/<owner>/*`, or import a platform BOM (for example
`cloud-core-quarkus-bom-publish`). Without `read:packages` credentials the local
Maven build documented in the service's own install guide fails with HTTP 401.
Record `build blocked: private-registry — maven.pkg.github.com/<owner>`; the
handling is the shared one.

Before recording it, rule out the two Maven-specific false positives:

- run with `--batch-mode` and keep full logs visible, so a slow dependency resolve
  is not mistaken for an auth failure;
- for multi-module reactors, build from the repository root with module-closure
  flags (`-pl ... -am`, or the documented equivalent) so sibling artifacts resolve.

Do **not** improvise substitutes: no OTel Java agent on a stock image, no patched
JARs, no building sibling monorepos to fake BOM versions.

## Provenance evidence

When a pre-built image is reused, before accepting `ci-image`:

1. compare image labels and the Quarkus version in the startup log against
   `pom.xml` (`quarkus.platform.version`, artifact version);
2. confirm `quarkus-opentelemetry` (or the target stack) appears in
   `Installed features` at boot.
