# Layer 5 — Validation (Go)

Shared tiers, `validationPlan` structure, static/configuration checks, runtime
gating, and pass/fail rules:

[`opentelemetry-tracing-common/models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md).

Go execution is assembled from the files below; this layer only routes to them.

| Concern | Where |
| --- | --- |
| Runtime path and install commands | common [`reference/service-installation-discovery.md`](../../opentelemetry-tracing-common/reference/service-installation-discovery.md) |
| What counts as the build check | [`../reference/build-preconditions.md`](../reference/build-preconditions.md) |
| The one post-L4 build and image | [`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md) |
| Stand, traffic, assertions, teardown, "no spans" diagnosis | [`../recipes/validation-stack.md`](../recipes/validation-stack.md) |
| Runtime order and pass/fail gates | common [`models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md) §5.3 |
