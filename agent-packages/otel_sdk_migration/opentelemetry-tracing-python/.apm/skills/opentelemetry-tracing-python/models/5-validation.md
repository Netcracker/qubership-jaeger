# Layer 5 — Validation (Python)

Shared tiers, `validationPlan` structure, static/configuration checks, runtime gating, and pass/fail rules:

[`opentelemetry-tracing-common/models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md).

Python execution is assembled from the files below; this layer only routes to them.

| Concern | Where |
| --- | --- |
| Runtime path and install commands | [`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md) |
| What counts as the build check (no compiler — the install is the verification) | [`../reference/build-preconditions.md`](../reference/build-preconditions.md) |
| The one post-L4 install and image | [`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md) |
| Stand, traffic, assertions, teardown, "no spans" diagnosis | [`../recipes/validation-stack.md`](../recipes/validation-stack.md) |
| Runtime order and pass/fail gates | common [`models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md) §5.3 |

One Python-specific reading of the shared entry-span assertion: under a
pre-forked server the span must come from a **worker**, not the master — a
provider initialized before the fork exports nothing from the workers
([`../recipes/validation-stack.md`](../recipes/validation-stack.md)).
