# Build and registry notes (Go)

Use this file to **detect** build blockers and enforce **fresh-build** rules
before runtime end-to-end.

**Runtime end-to-end after Layer 4:** the agent **must** run
[`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md)
(`go test`/`go build` + container image in the same session) before runtime deploy.
Plan-only / audit runs without runtime deploy may defer build and set
`validationPlan.runtime.status` to `manual`.

Install path discovery:
[`service-installation-discovery.md`](service-installation-discovery.md).

## Private module registries

Some Go services use private module sources (GitHub Packages/internal mirrors).
If post-L4 build fails due to auth (401/403 or module download denied):

1. record blocker in `gaps` (`runtime.buildBlocked: private-go-module-registry`);
2. set `validationPlan.runtime.status` to `manual` unless user provides credentials
   or a prebuilt image path from install docs;
3. do **not** validate runtime on stale pre-L4 image or improvise substitute builds.

Distinguish **auth failure** (401/403, module access denied) from **slow resolve**
(download in progress, no error yet).

## Smoke vs validation

A stock image or pre-existing tag proves **availability**, not that the tracing
migration works. Never mark the runtime tier `pass` unless the running artifact
includes Layer 4 changes (dependencies, config, instrumentation mechanism).

Jaeger spans from probe traffic on a **crash-looping or not-Ready** workload are
**smoke only**, not validation — run umbrella
[`recipes/stand-health-gate.md`](../../opentelemetry-tracing-umbrella/recipes/stand-health-gate.md)
before tracing pass/fail.

## Build artifact provenance (mandatory for runtime pass)

Before runtime end-to-end, run [`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md).
**Every** Go validation session must:

1. **Purge** stale build outputs (`bin/`, `dist/`, module-specific dirs) and cached SUT images.
2. **`go test` / `go build`** (or install-doc equivalent) **after** Layer 4 edits.
3. **Build and load** a **new** container image with a session-unique tag.
4. **Deploy only that image** — never a tag left from a previous agent run.

Record how the SUT artifact was produced in the L5 summary and in
`validationPlan.runtime.buildProvenance`:

| Provenance                                                                                | Valid for L4 tracing validation?    |
|-------------------------------------------------------------------------------------------|-------------------------------------|
| Fresh **go build/test** + new image **in this session**                                   | **Yes** (default for `pass`)        |
| CI image tagged to the **current** commit/branch and proven to include current L4 changes | Yes, if provenance matches the diff |
| Pre-existing local image (`:e2e`, `:local`, `:latest`) without rebuild                    | **No** — max `fail`                 |
| Public/stock image without L4 changes                                                     | **No**                              |

Checklist when a pre-built image is reused:

1. Confirm the image was built **after** the current L4 changes (CI run, labels,
   digest, commit SHA).
2. Compare image build metadata with the current `go.mod` / L4 diff.
3. If provenance does not match the migrated tree, set `validationPlan.runtime.status`
   to `fail` or `manual` with gap `runtime.reusedImageNotFromCurrentL4Build` — do
   **not** claim the migration is validated.

Example honest summary:

> Runtime end-to-end used pre-existing image `<service>:<tag>` built before L4.
> Tracing export works on that image, but **L4 diff is not compile-verified**.
