# Layer 5 — Validation (TypeScript / Node)

Shared tiers, `validationPlan` structure, static/configuration checks, runtime gating, and pass/fail rules:

[`opentelemetry-tracing-common/models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md).

Node execution is assembled from the files below; this layer only routes to them.

| Concern | Where |
| --- | --- |
| Runtime path, install commands, lockfile provenance | [`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md) |
| What counts as the build check (typecheck on TS, clean install on plain JS) | [`../reference/build-preconditions.md`](../reference/build-preconditions.md) |
| The one post-L4 build and image | [`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md) |
| Stand, traffic, assertions, teardown, "no spans" diagnosis | [`../recipes/validation-stack.md`](../recipes/validation-stack.md) |
| Runtime order and pass/fail gates | common [`models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md) §5.3 |

One Node-specific reading of a shared assertion: `traceId`/`spanId` in logs must
carry the **contract** field names, not the `trace_id`/`span_id` that the pino,
winston, and bunyan instrumentations inject by default
([`../reference/detection-rules.md`](../reference/detection-rules.md)
§Log-correlation signatures). Correlation wired with the wrong field names is a
finding, not a pass.
