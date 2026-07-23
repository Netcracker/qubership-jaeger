# Layer 5 — Validation (Python)

Shared tiers, `validationPlan` structure, static/configuration checks, runtime
gating, and pass/fail rules:

[`opentelemetry-tracing-common/models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md).

Python execution details:

- runtime path must be discovered first via
  [`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md);
- post-L4 dependency reinstall + image build is mandatory before runtime end-to-end
  (Python is interpreted — the "fresh build" is a clean dependency install, not a
  compile; see the fresh-build gate below);
- stand health and log triage are mandatory before tracing pass/fail.

## Fresh build gate (once after L4)

Use [`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md):

1. purge stale build outputs (`build/`, `dist/`, `*.egg-info/`, `__pycache__/`)
   and stale SUT images;
2. run one post-L4 clean dependency install + smoke import from service docs
   (`pip install -r requirements.txt`, `poetry install`, or equivalent);
3. build image with session-unique tag;
4. deploy only that image (or documented CI image proving it contains current L4).

## Python tracing assertions

Beyond the shared runtime gates, assert:

- resolved `service.name` = `${name}-${namespace}` (no literal `${...}` in the
  exported resource);
- a **server span** on the exercised business endpoint (ASGI/WSGI span);
- **wire-header** propagation on outgoing calls (`b3` vs `X-B3-*` vs
  `traceparent`) — a shared `trace_id` alone passes with the wrong inject format;
- `traceId`/`spanId` present in the request's log lines.

## Runtime order

```text
deploy -> stand health gate -> log error triage -> business traffic -> tracing assertions -> pass/fail -> validation cleanup (on pass)
```

Recipes:

- [`../../opentelemetry-tracing-common/recipes/stand-health-gate.md`](../../opentelemetry-tracing-common/recipes/stand-health-gate.md)
- [`../../opentelemetry-tracing-common/recipes/log-error-triage.md`](../../opentelemetry-tracing-common/recipes/log-error-triage.md)
- [`../../opentelemetry-tracing-common/recipes/validation-cleanup.md`](../../opentelemetry-tracing-common/recipes/validation-cleanup.md)
