---
name: opentelemetry-tracing-ts
description: Audits distributed tracing in unknown TypeScript/Node services (Express, Fastify, NestJS, pure Node OTel SDK), scores maturity (levels 1-5), and produces OpenTelemetry migration and validation plans against the Qubership platform tracing contract. Use when the repository has no tracing, legacy tracing (Zipkin/OpenTracing/Jaeger client), hybrid or incomplete OTel, broken worker_threads/child_process/Kafka/message-queue context propagation, failed OTLP export, ESM/bundler or import-order breakage, or work touching TRACING_* variables, sampling, B3/b3multi/W3C propagation, traceId/spanId log correlation, package.json tracing dependencies, or Helm tracing values — including when the user only mentions tracing, spans, Jaeger, OpenTelemetry, or broken/missing traces without naming this skill. Prefer over generic OTel advice for any TypeScript/Node tracing change to code, config, Helm, or dependencies. Do NOT use for Java/Go/Python services.
---

# OpenTelemetry tracing audit & migration engine (TypeScript / Node)

This skill is an analysis pipeline. It takes an unknown TypeScript/Node repository
as input and produces five machine-readable artifacts: discovery profile,
capability assessment, maturity verdict, migration plan, and validation plan.

Read common platform contract first:
[`platform-tracing-guide.md`](../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
— it is the binding source for `TRACING_*` parameters, OTLP export shape,
B3/B3Multi propagation, sampling, service naming, endpoint filtering, and log
correlation. Auto-instrumentation and framework middleware are allowed only when
they preserve that contract.

## 1. When to apply

Use for:

- enabling or auditing distributed tracing in TypeScript/Node services;
- migrating legacy stacks (Zipkin/OpenTracing/Jaeger client) to OTel;
- fixing incomplete OTel (API only, missing exporter, broken OTLP endpoint);
- fixing context propagation loss across worker_threads/child_process/Kafka/message queues;
- fixing ESM/bundler or import-order breakage that silences instrumentation;
- work touching `TRACING_*`, OTLP, sampling, propagators, or trace-log correlation.

Do not use for Java/Go/Python services.

## 2. Pipeline overview

```text
repository
   │
   ▼
[L1] Discovery   ──► discovery-result.json
   │
   ▼
[L2] Capability  ──► capability-result.json
   │
   ▼
[L3] Maturity    ──► maturity-result.json
   │
   ▼
[L4] Transformation ─► migration-plan.json
   │
   ▼
[L5] Validation  ──► validationPlan (embedded in migration-plan)
```

Layer ownership:

- L1: this package (`models/1-discovery.md`, TypeScript rules and recipes)
- L2-L5: common shared logic with TypeScript runtime execution details

## 3. Execution order

### 3.0 Mandatory phase split

**Phase 1 (read-only):** L1-L3 and three user briefs.

During Phase 1, do not:

- edit source/config/Helm/docs;
- run build/image/runtime deploy;
- apply L4 recipes.

**Phase 2 (implementation):** L4 + one post-L4 build + L5 validation.

**Multi-language repository:** if the repository contains services in **other language
families** besides TypeScript/Node, run the common
[Multi-language scope gate](../opentelemetry-tracing-common/SKILL.md)
— ask the user **bulk vs single target** before any L4 edit.

### 3.1 User-facing briefs (mandatory)

After each L1, L2, L3 artifact, post a short brief:

- L1: framework stack (`service.framework`), module system (ESM/CJS) and whether
  the runtime artifact is bundled, dependency buckets, export/sampling,
  instrumentation mode and mechanism plus the bootstrap load hook (`-r` /
  `--import` / loader), async hotspots, platform gaps. State **propagation as two
  directions** in plain words — what is accepted inbound vs what is sent outbound
  — and name the source of each (explicit config, or an SDK/instrumentation
  default). "Not configured" is not "not propagating".
- L2: propagation verdict, span quality, export path, platform compliance. Report
  inbound and outbound compatibility **separately** — a service can read incoming
  traces fine and still emit a format its peers ignore, which no end-to-end test
  will show (in Node this is the `new B3Propagator()` single-`b3` default vs the
  contract `b3multi`).
- L3: current level, recommended work in prose, target level (if L4 planned),
  **migration path** (`Migration path: Level N → Level M` when L4 planned),
  blockers.

### 3.2 Post-L4 build rule (once)

When L4 edits exist:

1. run fresh build and image once (see `recipes/fresh-build-and-image.md`);
2. do not rebuild again for runtime if L4 files are unchanged;
3. never validate runtime on stale image built before L4.

### 3.3 Runtime opt-in

After successful post-L4 build, ask user before runtime deploy.
If user declines or environment is unknown, set runtime status to `manual`.

### 3.4 Runtime order

Common §5.3 — execute in order:

```text
deploy -> stand health -> log error triage -> business traffic -> tracing assertions -> pass/fail -> teardown
```

Teardown has two halves with different triggers: the **runtime resources** created
for the stand (throwaway backend, `TRACING_HOST` alias, temporary namespace) come
down **whatever the verdict is** — see
[`recipes/validation-stack.md`](recipes/validation-stack.md) §Teardown — while the
**repository files** created for L5 are cleaned only on `pass` (§3.5).

Recipes (common):

- [`recipes/stand-health-gate.md`](../opentelemetry-tracing-common/recipes/stand-health-gate.md)
- [`recipes/log-error-triage.md`](../opentelemetry-tracing-common/recipes/log-error-triage.md)

Never do Jaeger-first pass/fail.

### 3.5 Post-validation cleanup (mandatory after runtime `pass`)

When `validationPlan.runtime.status` is `pass`, run
[`recipes/validation-cleanup.md`](../opentelemetry-tracing-common/recipes/validation-cleanup.md). See common
[`models/5-validation.md`](../opentelemetry-tracing-common/models/5-validation.md)
§5.4.

## 4. Output contract

Produce:

- `discovery-result.json` (TypeScript schema in this package)
- `capability-result.json` (common schema redirect)
- `maturity-result.json` (common schema redirect)
- `migration-plan.json` (common schema redirect; includes `validationPlan`)

## 5. Non-negotiable rules

| Rule | Reason |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Platform contract is binding | Must enforce `TRACING_*`, OTLP `http/protobuf`, `b3multi`, `parentbased_traceidratio`, `${name}-${namespace}`, endpoint filtering, trace IDs in logs |
| Evidence-first | Every claim cites file/path/env key |
| No semantic auto-rename | Semantic-convention renames are proposals, not automatic edits |
| One tracing stack | Final state cannot keep legacy Zipkin/OpenTracing/Jaeger as active stack |
| One instrumentation mechanism | Register each library once, through one path: the `@opentelemetry/auto-instrumentations-node/register` launcher, **or** `NodeSDK({ instrumentations })`, **or** a standalone `registerInstrumentations()` — never two of them for the same library, because double instrumentation can duplicate spans. `@fastify/otel` is a Fastify plugin and is never wired by the launcher at all |
| One propagator registration | Set the propagator once, as `textMapPropagator` on the SDK. `@opentelemetry/api` refuses a duplicate global registration, so a `setGlobalPropagator()` call after `sdk.start()` returns `false`, logs `Attempted duplicate registration of API: propagation`, and silently changes nothing |
| `fetch()` needs its own instrumentation | Node's global `fetch` is undici, not the `http` module: without `@opentelemetry/instrumentation-undici` there is no client span **and no trace headers on the wire**, so every downstream service starts a new root trace while this service's own spans look correct |
| Load tracing first | The tracing bootstrap must initialize before any instrumented module is imported; ESM `import` hoisting or a bundler that inlines requires silently defeats monkey-patch instrumentation |
| Correct OTLP encoding | `http/protobuf` = `@opentelemetry/exporter-trace-otlp-proto`; `-otlp-http` ships JSON, `-otlp-grpc` ships gRPC — picking the wrong package silently breaks the contract format |
| Sampling & propagation mandatory | Validation fails if unknown or unverified |
| Defer versions | Read versions from `package.json`/lockfile, never hardcode versions in skill text |
| Sync docs on L4 | If L4 changes config/env/deps, update service docs in the same pass |
| Fresh post-L4 build | Runtime pass requires a post-L4 clean install (frozen when a lockfile is committed, refreshed first because L4 changed the manifest), the build check the repository actually has (`tsc` on TypeScript, the bootstrap smoke run on plain JavaScript), and image provenance |
| End-to-end only when stand is healthy | Runtime `pass` needs stand health + log triage before Jaeger (§3.4; common L5) |
| No Jaeger-first pass | Jaeger spans while SUT crash-loops or not Ready are not end-to-end pass — fix the stand first |

## 6. File index

- Models: [`models/`](models/) — L4 framework/mechanism gate in [`models/4-transformation.md`](models/4-transformation.md); L5 TypeScript delta in [`models/5-validation.md`](models/5-validation.md)
- Schemas: [`schemas/`](schemas/)
- Detection signatures: [`reference/detection-rules.md`](reference/detection-rules.md)
- Framework → instrumentation coverage (single source of truth): [`reference/framework-coverage.md`](reference/framework-coverage.md)
- Build blockers: [`reference/build-preconditions.md`](reference/build-preconditions.md)
- Runtime install discovery: [`reference/service-installation-discovery.md`](reference/service-installation-discovery.md)
- Recipes: [`recipes/`](recipes/) — L4 apply + `fresh-build-and-image`, `validation-stack`
- Shared L5 runtime (common): [`recipes/stand-health-gate.md`](../opentelemetry-tracing-common/recipes/stand-health-gate.md), [`recipes/log-error-triage.md`](../opentelemetry-tracing-common/recipes/log-error-triage.md), [`recipes/validation-cleanup.md`](../opentelemetry-tracing-common/recipes/validation-cleanup.md)
