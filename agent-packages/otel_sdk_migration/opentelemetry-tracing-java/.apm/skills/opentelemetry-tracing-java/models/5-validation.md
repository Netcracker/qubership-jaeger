# Layer 5 — Validation (Java)

Shared tiers, `validationPlan` structure, static and configuration checks, runtime order, and pass/fail rules:
[`opentelemetry-tracing-common/models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md).

This file adds the Java **execution** details only.

## Before runtime: install path and build

1. **Find the install path** — common
   [`reference/service-installation-discovery.md`](../../opentelemetry-tracing-common/reference/service-installation-discovery.md).
   Runtime validation is not "build and deploy whatever we touched": the target app and install scope are unknown
   until discovery runs. Do not add a second undocumented pipeline.
2. **Fresh build once** — [`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md), after all L4
   edits and before the first runtime deploy. Never run Maven during L1–L3, and never run a second full rebuild for
   end-to-end when the post-L4 build succeeded and L4 files are unchanged. Verify provenance instead: runner JAR mtime
   after the last L4 edit, and the image tag recorded in the brief.
3. **Blockers** — private registry or missing credentials: common
   [`reference/build-preconditions.md`](../../opentelemetry-tracing-common/reference/build-preconditions.md) plus the
   [Java delta](../reference/build-preconditions.md). Set `validationPlan.runtime.status` to `manual`; do not deploy a
   cached image as a workaround.

Static and configuration tiers never trigger a rebuild — inspect repository files only. Runtime end-to-end must use
either the fresh post-L4 image from this session, or a post-L4 image whose provenance still matches the current L4
edits.

## Environment questionnaire (runtime opt-in only)

Ask only after the install path is documented or confirmed, and only if runtime validation is still wanted:

1. **Where does the service run?** The user names a concrete environment with deploy permissions — never assume one.
2. **Tracing backend** — an existing collector or Jaeger, or the throwaway stand from common
   [`recipes/validation-stack.md`](../../opentelemetry-tracing-common/recipes/validation-stack.md) and the
   [Java delta](../recipes/validation-stack.md).
3. **Service dependencies** — from install docs (DB, secrets, volumes), not guessed. Reuse the repository's own
   Kubernetes or Helm manifests where they exist.

If the user declines or cannot answer, keep `runtime.status` at `manual`.

## Java tracing assertions

On top of the shared assertions, a Java runtime `pass` checks:

- `service.name = <name>-<namespace>`, **resolved** — a literal `${NAMESPACE:unknown}` surviving into the exported
  resource is a contract violation, not a cosmetic issue;
- `span.kind = server` on the exercised business endpoint. Do not default to `/v3/api-docs`, `/q/*`, `/actuator/*`, or
  probe URLs — they are on the suppression list;
- non-empty `traceId` and `spanId` in the service logs for that same request;
- one `trace_id` across async hops where the service has them;
- no recurring OTLP export errors in the SUT logs.

If the user asks about log errors, answer with the classified verdict from the triage recipe — never "there are errors
but it's fine" without evidence.

If the service never started because install or build was out of scope or blocked, set `runtime.status` to `manual` or
`fail` with the reason. Static and configuration alone are never a `pass`.
