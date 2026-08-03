# Layer 5 — Validation (Java)

Shared tiers, `validationPlan` structure, static and configuration checks, runtime order, and pass/fail rules:
[`opentelemetry-tracing-common/models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md).

This file adds the Java **execution** details only.

Java execution is assembled from the files below; this layer only routes to them.

| Concern | Where |
| --- | --- |
| Runtime path, install commands, the questions to ask | common [`reference/service-installation-discovery.md`](../../opentelemetry-tracing-common/reference/service-installation-discovery.md) |
| Build check, blockers, provenance | [`../reference/build-preconditions.md`](../reference/build-preconditions.md) |
| The one post-L4 build and image | [`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md) |
| Stand, traffic, assertions, teardown | [`../recipes/validation-stack.md`](../recipes/validation-stack.md) |
| Runtime order, prerequisites, pass/fail gates | common [`models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md) §5.3 |

## Java tracing assertions

On top of the shared assertions, a Java runtime `pass` checks:

- `service.name = <name>-<namespace>`, **resolved** — a literal `${NAMESPACE:unknown}` surviving into the exported
  resource is a contract violation, not a cosmetic issue;
- `span.kind = server` on the exercised business endpoint. Do not default to `/v3/api-docs`, `/q/*`, `/actuator/*`, or
  probe URLs — they are on the suppression list;
- one `trace_id` across async hops where the service has them;
- no recurring OTLP export errors in the SUT logs.

Verify provenance rather than rebuilding: the runner JAR mtime is after the last L4 edit, and the image tag matches the
one recorded in the brief.
