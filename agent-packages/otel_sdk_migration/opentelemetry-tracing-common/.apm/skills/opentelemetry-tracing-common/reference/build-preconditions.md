# Build and registry notes (shared)

Detect build blockers and enforce **fresh-build** rules before runtime end-to-end.
Language packages add only what differs — the build command, the registry flavour,
and any language-specific blocker. Everything below applies to all of them.

**Runtime end-to-end after Layer 4:** run the language
`recipes/fresh-build-and-image.md` (build check + container image in the same
session) before runtime deploy. Plan-only or audit runs without runtime deploy may
defer the build and set `validationPlan.runtime.status` to `manual`.

Install path discovery: [`service-installation-discovery.md`](service-installation-discovery.md).

## Private registries

Services commonly resolve dependencies from a private source (internal mirror,
GitHub Packages, scoped registry, private index). When a post-L4 build or install
fails on authentication (401/403, or a download denied):

1. record the blocker in plan `gaps` (`build blocked: private-registry — <registry or scope>`);
2. set `validationPlan.runtime.status` to `manual` unless the user supplies
   credentials or a prebuilt image path from install docs;
3. do **not** validate runtime on a stale pre-L4 image, and do **not** improvise a substitute install.

Distinguish **auth failure** (401/403, access denied) from **slow resolve** (download
or dependency resolution in progress, no error yet). Do not encode host-OS assumptions:
before recording the blocker, check that the build runtime can reach the credential
source the repository owner expects (settings file, token injection, CI secret, wrapper).

## Smoke vs validation

A stock image or a pre-existing tag proves **availability**, not that the tracing
migration works. Never mark the runtime tier `pass` unless the running artifact
includes the Layer 4 changes (dependencies, config, instrumentation mechanism).
The workload must also be healthy first —
[`../recipes/stand-health-gate.md`](../recipes/stand-health-gate.md).

## Build artifact provenance (mandatory for runtime pass)

Every validation session runs the language fresh-build recipe: purge stale build
output and cached SUT images → build check after Layer 4 → build a session-unique
image → deploy only that image, never a tag left from a previous agent run.

Record how the SUT artifact was produced in the L5 summary and in `validationPlan.runtime.buildProvenance`.
The `source` column is the schema enum value to write:

| Provenance                                                                             | `source`             | Valid for L4 tracing validation?                      |
|----------------------------------------------------------------------------------------|----------------------|-------------------------------------------------------|
| Fresh language build check + new image **in this session**                             | `fresh-build`        | **Yes** (default for `pass`)                          |
| CI image tagged to the **current** commit/branch, proven to include current L4 changes | `ci-image`           | Yes, if provenance matches the diff                   |
| Pre-existing local image (`:e2e`, `:local`, `:latest`) without rebuild                 | `reused-local-image` | **No** — `manual`, or `fail` if runtime was exercised |
| Public/stock image without L4 changes                                                  | `stock-image`        | **No**                                                |

Record the commands actually run in `buildProvenance.detail`, together with
`buildCommand`, `imageTag`, `runnerArtifact`, and `purgedImages`.

Checklist when a pre-built image is reused:

1. Confirm the image was built **after** the current L4 changes (CI run, labels, digest, commit SHA, registry metadata).
2. Compare the image's dependency set with the current manifest and L4 diff.
3. If provenance does not match the migrated tree, set `validationPlan.runtime.status` to `fail` or
   `manual` with gap `runtime.reusedImageNotFromCurrentL4Build` — do **not** claim the migration is validated.

Example honest summary:

> Runtime end-to-end used pre-existing image `<service>:<tag>` built before L4.
> Tracing export works on that image, but the **L4 diff is not build-verified**.
