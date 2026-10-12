# Build and registry notes — Python delta

Shared blocker handling, smoke-vs-validation rule, and the provenance table:
[`opentelemetry-tracing-common/reference/build-preconditions.md`](../../opentelemetry-tracing-common/reference/build-preconditions.md).

Python specifics below.

## No compiler — the install is the verification

Python has no compile step, so a wrong import or a missing dependency fails only at
**runtime**. The fresh-build recipe compensates: a clean `pip install` /
`poetry install` / `uv sync` in a throwaway environment, plus an explicit `import`
of the OTel SDK and of the service entry module, is the closest analogue to a
compile check. A migration that "looks applied" in source but was never installed
into the image is unverified — treat it as such.

That install-and-import pair is the post-L4 build check, followed by a container
image with a session-unique tag —
[`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md). Write
the install command into `buildProvenance.buildCommand`.

## Private package indices

Python services often install from a private index (internal PyPI mirror, GitHub
Packages, `--extra-index-url`, `[[tool.poetry.source]]`). Record the blocker as
`build blocked: private-registry — <index URL>`; the handling is the shared one.
A backtracking resolver can run for minutes without an error — that is a slow
resolve, not an auth failure.

## Provenance evidence

When a pre-built image is reused, compare its installed package set against the
current manifest and the L4 diff (`pip show opentelemetry-sdk` inside the image)
before accepting `ci-image`.
