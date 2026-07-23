# Build and registry notes (Python)

Use this file to **detect** build blockers and enforce **fresh-build** rules
before runtime end-to-end.

**Runtime end-to-end after Layer 4:** the agent **must** run
[`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md)
(clean dependency install + smoke import + container image in the same session)
before runtime deploy. Plan-only / audit runs without runtime deploy may defer
build and set `validationPlan.runtime.status` to `manual`.

Install path discovery:
[`service-installation-discovery.md`](service-installation-discovery.md).

## No compiler — install is the verification

Python has no compile step, so a wrong import or a missing dependency only fails
at **runtime**. The fresh-build recipe compensates: a clean `pip install` /
`poetry install` in a throwaway environment plus an explicit `import` of the OTel
SDK and the service entry module is the closest analogue to a compile check. A
migration that "looks applied" in source but was never installed into the image
is unverified — treat it as such.

## Private package indexes

Some Python services install from private indexes (internal PyPI mirror, GitHub
Packages, `--extra-index-url`, `[[tool.poetry.source]]`). If post-L4 install fails
due to auth (401/403 or package download denied):

1. record blocker in `gaps` (`runtime.buildBlocked: private-python-index`);
2. set `validationPlan.runtime.status` to `manual` unless the user provides
   credentials or a prebuilt image path from install docs;
3. do **not** validate runtime on a stale pre-L4 image or improvise a substitute
   install.

Distinguish **auth failure** (401/403, index access denied) from **slow resolve**
(download/backtracking in progress, no error yet).

## Smoke vs validation

A stock image or pre-existing tag proves **availability**, not that the tracing
migration works. Never mark the runtime tier `pass` unless the running artifact
includes Layer 4 changes (dependencies, config, instrumentation mechanism).

Jaeger spans from probe traffic on a **crash-looping or not-Ready** workload are
**smoke only**, not validation — run common
[`recipes/stand-health-gate.md`](../../opentelemetry-tracing-common/recipes/stand-health-gate.md)
before tracing pass/fail.

## Build artifact provenance (mandatory for runtime pass)

Before runtime end-to-end, run [`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md).
**Every** Python validation session must:

1. **Purge** stale build outputs (`build/`, `dist/`, `*.egg-info/`, `__pycache__/`) and cached SUT images.
2. **Clean install + smoke import** (`pip install` / `poetry install` + `import`) **after** Layer 4 edits.
3. **Build and load** a **new** container image with a session-unique tag.
4. **Deploy only that image** — never a tag left from a previous agent run.

Record how the SUT artifact was produced in the L5 summary and in
`validationPlan.runtime.buildProvenance`:

| Provenance                                                                                | Valid for L4 tracing validation?    |
|-------------------------------------------------------------------------------------------|-------------------------------------|
| Fresh **clean install + smoke** + new image **in this session**                           | **Yes** (default for `pass`)        |
| CI image tagged to the **current** commit/branch and proven to include current L4 changes | Yes, if provenance matches the diff |
| Pre-existing local image (`:e2e`, `:local`, `:latest`) without reinstall                  | **No** — max `fail`                 |
| Public/stock image without L4 changes                                                     | **No**                              |

Checklist when a pre-built image is reused:

1. Confirm the image was built **after** the current L4 changes (CI run, labels,
   digest, commit SHA).
2. Compare the image's installed package set with the current manifest / L4 diff
   (`pip show opentelemetry-sdk` inside the image).
3. If provenance does not match the migrated tree, set `validationPlan.runtime.status`
   to `fail` or `manual` with gap `runtime.reusedImageNotFromCurrentL4Build` — do
   **not** claim the migration is validated.

Example honest summary:

> Runtime end-to-end used pre-existing image `<service>:<tag>` built before L4.
> Tracing export works on that image, but **L4 diff is not install-verified**.
