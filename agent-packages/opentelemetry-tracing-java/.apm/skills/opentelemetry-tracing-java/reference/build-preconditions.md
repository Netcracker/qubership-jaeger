# Build and registry notes

Use this file to **detect** registry blockers and enforce **fresh-build** rules
before runtime end-to-end.

**Runtime end-to-end after Layer 4:** the agent **must** run
[`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md)
(`mvn package` + container image build in the same session) before runtime deploy.
Plan-only / audit runs without runtime deploy may defer build and set
`validationPlan.runtime.status` to `manual`.

## Private package registries

Many Qubership/NC Java services declare:

- `<repositories>` pointing at `maven.pkg.github.com/<owner>/*`;
- platform BOM imports (e.g. `cloud-core-quarkus-bom-publish`).

Without `read:packages` credentials, a **local Maven build** documented in the
service's own install guide will fail with HTTP 401. When discovery or install
docs reference such registries:

1. Record `runtime.buildBlocked: private-maven-registry` (or equivalent) in
   `gaps`.
2. Set `validationPlan.runtime.status` to `manual` unless the user supplies
   credentials or a prebuilt image path from install docs.
3. Do **not** improvise substitutes (OTel Java agent on stock image, patching JARs,
   building sibling monorepos to fake BOM versions).

## Build-environment neutrality rules

Do not encode host-OS assumptions in the skill. Before recording
`runtime.buildBlocked: private-maven-registry`:

1. Verify that the active Maven runtime can access the credential source expected
   by the repository owner (settings file, token injection, CI secret, or wrapper).
2. Use `--batch-mode` for first-time validation and keep full logs visible; avoid
   shortcuts that hide slow dependency resolution.
3. Distinguish **auth failure** (HTTP 401, "authentication failed") from
   **slow resolve** (downloading artifacts, no error yet).
4. For multi-module reactors, build from the repository root with module-closure
   flags (`-pl ... -am` or the documented equivalent) so sibling artifacts resolve.

## Smoke vs. validation

A stock image or boot-without-migration proves **availability**, not that the
tracing migration works. Never mark the runtime tier `pass` unless the running
artifact includes the Layer 4 changes (dependencies, config, correct
instrumentation mechanism).

Jaeger spans from probe traffic on a **crash-looping or not-Ready** pod are
**smoke only**, not validation — run
[`../../opentelemetry-tracing-umbrella/recipes/stand-health-gate.md`](../../opentelemetry-tracing-umbrella/recipes/stand-health-gate.md) before
tracing pass/fail.

## Build artifact provenance (mandatory for runtime pass)

Before runtime end-to-end, run [`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md).
**Every** Java validation session must:

1. **Purge** stale `target/` output and cached SUT container images.
2. **`mvn clean package`** (or Gradle equivalent) **after** Layer 4 edits.
3. **Build and load** a **new** container image with a session-unique tag.
4. **Deploy only that image** — never a tag left from a previous agent run.

Record how the SUT artifact was produced in the L5 summary and in
`validationPlan.runtime.buildProvenance`:

| Provenance | Valid for L4 tracing validation? |
| --- | --- |
| Fresh Maven/Gradle **clean package** + new image **in this session** | **Yes** (default requirement for `pass`) |
| CI image tagged to current commit/branch with current L4 changes | Yes, if provenance matches the diff |
| Pre-existing local image (`:e2e`, `:local`, `:latest`) without rebuild | **No** — max `fail` |
| Public/stock image without L4 changes | **No** |

Checklist when a pre-built image is reused:

1. Confirm the image was built **after** the current L4 changes (CI run, image
   labels, digest, commit SHA, or registry metadata).
2. Compare image labels / Quarkus version in startup log with `pom.xml`
   (`quarkus.platform.version`, artifact version).
3. Confirm `quarkus-opentelemetry` (or target stack) appears in
   `Installed features` at boot.
4. If versions, labels, or features do not match the migrated tree, set
   `validationPlan.runtime.status` to `fail` or `manual` with gap
   `runtime.reusedImageNotFromCurrentL4Build` — do **not** claim the migration
   is validated.

Example honest summary:

> Runtime end-to-end used pre-existing image `<service>:<tag>` built before L4.
> Tracing export works on that image, but **L4 diff is not compile-verified**.
