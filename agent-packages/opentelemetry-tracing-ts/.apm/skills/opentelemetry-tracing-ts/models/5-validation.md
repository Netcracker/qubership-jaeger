# Layer 5 — Validation (TypeScript / Node)

Shared tiers, `validationPlan` structure, static/configuration checks, runtime gating, and pass/fail rules:

[`opentelemetry-tracing-common/models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md).

TypeScript/Node execution details:

- runtime path must be discovered first via
  [`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md);
- post-L4 clean install (`npm ci` / `yarn install --frozen-lockfile` /
  `pnpm i --frozen-lockfile`) + image build is mandatory before runtime
  end-to-end. `npm ci` needs a committed lockfile — without one, use `npm install`
  and record the weaker provenance in `gaps`;
- when the repository is TypeScript, the typecheck **is** the compile-check and
  the build must pass before the image is trusted. A plain-JavaScript service has
  no compile step: the gate there is the clean install plus the documented
  build/bundle script when one exists. Do not fail a JS service for a missing
  `tsc` run;
- the runtime tier itself (throwaway backend, sampler `1.0` for the smoke, traffic,
  assertions) runs from [`../recipes/validation-stack.md`](../recipes/validation-stack.md);
- stand health and log triage are mandatory before tracing pass/fail.

## Fresh build gate (once after L4)

Use [`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md):

1. purge stale SUT images and stale build output (`dist/`, `build/`, `.tsbuildinfo`, bundler caches);
2. run one post-L4 clean install, then the build step the repository actually has
   (`npm ci && npm run build`, `tsc --noEmit` on TypeScript, or the documented
   bundler command; clean install alone on a plain-JavaScript service with no
   build script);
3. build image with session-unique tag;
4. deploy only that image (or documented CI image proving it contains current L4).

## TypeScript/Node tracing assertions

Beyond the shared runtime gates, assert:

- resolved `service.name` = `${name}-${namespace}` (no literal `${...}` in the exported resource);
- an **entry span** on the exercised unit of work: a server span for an HTTP or
  framework service; for a `pure-node` worker or consumer, the consumer span
  (`kafkajs`/`amqplib`/queue instrumentation) carrying the producer's context as
  parent or link. A worker has no server span — asserting one there fails a
  correct migration;
- **wire-header** propagation on outgoing calls (`b3` vs `X-B3-*` vs
  `traceparent`) — a shared `trace_id` alone passes with the wrong inject format,
  and in Node `new B3Propagator()` emits single `b3` while the plan may say `b3multi`;
- `traceId`/`spanId` present in the request's log lines (contract field names, not
  the `trace_id`/`span_id` that pino/winston instrumentation inject by default);
- (when bundled or ESM) that instrumentation actually attached — the entry span
  appearing at all confirms the load-order/bundler fix worked.

## Runtime order

Canonical definition: common
[`models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md)
§5.3. Repeated here for execution:

```text
deploy -> stand health gate -> log error triage -> business traffic -> tracing assertions -> pass/fail -> validation cleanup (on pass)
```

Recipes:

- [`../../opentelemetry-tracing-common/recipes/stand-health-gate.md`](../../opentelemetry-tracing-common/recipes/stand-health-gate.md)
- [`../../opentelemetry-tracing-common/recipes/log-error-triage.md`](../../opentelemetry-tracing-common/recipes/log-error-triage.md)
- [`../../opentelemetry-tracing-common/recipes/validation-cleanup.md`](../../opentelemetry-tracing-common/recipes/validation-cleanup.md)
