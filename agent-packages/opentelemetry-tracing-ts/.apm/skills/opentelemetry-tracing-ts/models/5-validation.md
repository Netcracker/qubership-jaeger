# Layer 5 — Validation (TypeScript / Node)

Shared tiers, `validationPlan` structure, static/configuration checks, runtime gating, and pass/fail rules:

[`opentelemetry-tracing-common/models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md).

TypeScript/Node execution details:

- runtime path must be discovered first via
  [`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md);
- post-L4 clean install (`npm ci` / `yarn install --frozen-lockfile` /
  `pnpm i --frozen-lockfile`) + typecheck/compile + image build is mandatory
  before runtime end-to-end (unlike Python, TypeScript **has** a compile step —
  the typecheck is the compile-check; see the fresh-build gate below);
- stand health and log triage are mandatory before tracing pass/fail.

## Fresh build gate (once after L4)

Use [`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md):

1. purge stale SUT images and stale build output (`dist/`, `build/`, `.tsbuildinfo`, bundler caches);
2. run one post-L4 clean install + typecheck/compile from service docs
   (`npm ci && npm run build`, `tsc --noEmit`, or the documented bundler command);
3. build image with session-unique tag;
4. deploy only that image (or documented CI image proving it contains current L4).

## TypeScript/Node tracing assertions

Beyond the shared runtime gates, assert:

- resolved `service.name` = `${name}-${namespace}` (no literal `${...}` in the exported resource);
- a **server span** on the exercised business endpoint (HTTP/framework span);
- **wire-header** propagation on outgoing calls (`b3` vs `X-B3-*` vs
  `traceparent`) — a shared `trace_id` alone passes with the wrong inject format,
  and in Node `new B3Propagator()` emits single `b3` while the plan may say `b3multi`;
- `traceId`/`spanId` present in the request's log lines (contract field names, not
  the `trace_id`/`span_id` that pino/winston instrumentation inject by default);
- (when bundled or ESM) that instrumentation actually attached — a server span
  appearing at all confirms the load-order/bundler fix worked.

## Runtime order

```text
deploy -> stand health gate -> log error triage -> business traffic -> tracing assertions -> pass/fail -> validation cleanup (on pass)
```

Recipes:

- [`../../opentelemetry-tracing-common/recipes/stand-health-gate.md`](../../opentelemetry-tracing-common/recipes/stand-health-gate.md)
- [`../../opentelemetry-tracing-common/recipes/log-error-triage.md`](../../opentelemetry-tracing-common/recipes/log-error-triage.md)
- [`../../opentelemetry-tracing-common/recipes/validation-cleanup.md`](../../opentelemetry-tracing-common/recipes/validation-cleanup.md)
