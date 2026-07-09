# Layer 5 — Validation (Go)

Shared tiers, `validationPlan` structure, static/configuration checks, runtime
gating, and pass/fail rules:

[`opentelemetry-tracing-umbrella/models/5-validation.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/models/5-validation.md).

Go execution details:

- runtime path must be discovered first via
  [`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md);
- post-L4 build/image is mandatory before runtime end-to-end;
- stand health and log triage are mandatory before tracing pass/fail.

## Fresh build gate (once after L4)

Use [`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md):

1. purge stale build outputs and stale SUT images;
2. run one post-L4 Go build/test command from service docs;
3. build image with session-unique tag;
4. deploy only that image (or documented CI image proving it contains current L4).

## Runtime order

```text
deploy -> stand health gate -> log error triage -> business traffic -> tracing assertions -> pass/fail -> validation cleanup (on pass)
```

Recipes:

- [`../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/stand-health-gate.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/stand-health-gate.md)
- [`../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/log-error-triage.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/log-error-triage.md)
- [`../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/validation-cleanup.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/validation-cleanup.md)
