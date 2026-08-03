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
- L2–L5: common shared logic, with the TypeScript gates and runtime execution in this package

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

Content and rules for all three briefs: common
[`reference/user-briefs.md`](../opentelemetry-tracing-common/reference/user-briefs.md).

TypeScript adds to the L1 brief:

- **framework stack** — `service.framework` from L1: Express, Fastify, NestJS, or pure Node;
- **module system** (ESM/CJS) and whether the runtime artifact is bundled;
- **instrumentation mechanism** and the bootstrap load hook (`-r`, `--import`, or loader) — on Node this decides
  whether instrumentation runs at all, not just how it is configured.

### 3.2 Post-L4 build rule (once)

When L4 edits exist:

1. run fresh build and image once (see `recipes/fresh-build-and-image.md`);
2. do not rebuild again for runtime if L4 files are unchanged;
3. never validate runtime on stale image built before L4.

### 3.3 Runtime opt-in

After successful post-L4 build, ask user before runtime deploy.
If user declines or environment is unknown, set runtime status to `manual`.

### 3.4 Runtime order

Stand, order, assertions, and teardown: common
[`recipes/validation-stack.md`](../opentelemetry-tracing-common/recipes/validation-stack.md) and the
[TypeScript delta](recipes/validation-stack.md). Never do a Jaeger-first pass/fail.

### 3.5 Post-validation cleanup (mandatory after runtime `pass`)

When `validationPlan.runtime.status` is `pass`, run
[`recipes/validation-cleanup.md`](../opentelemetry-tracing-common/recipes/validation-cleanup.md). See common
[`models/5-validation.md`](../opentelemetry-tracing-common/models/5-validation.md)
§5.4.

## 4. Output contract

The artifacts are in-session data, never files on disk — common
[`SKILL.md`](../opentelemetry-tracing-common/SKILL.md) §Where the artifacts live.

- `discovery-result` → [`schemas/L1-discovery-result.schema.json`](schemas/L1-discovery-result.schema.json)
- `capability-result` → common [`schemas/L2-capability-result.schema.json`](../opentelemetry-tracing-common/schemas/L2-capability-result.schema.json)
- `maturity-result` → common [`schemas/L3-maturity-result.schema.json`](../opentelemetry-tracing-common/schemas/L3-maturity-result.schema.json)
- `migration-plan` → common [`schemas/L4-migration-plan.schema.json`](../opentelemetry-tracing-common/schemas/L4-migration-plan.schema.json),
  including the embedded `validationPlan`

## 5. Non-negotiable rules

| Rule                                    | Reason                                                                                                                                                                                                                                                                                                                                |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Platform contract is binding            | Must enforce `TRACING_*`, OTLP `http/protobuf`, `b3multi`, `parentbased_traceidratio`, `${name}-${namespace}`, endpoint filtering, trace IDs in logs                                                                                                                                                                                  |
| Evidence-first                          | Every claim cites file/path/env key                                                                                                                                                                                                                                                                                                   |
| No semantic auto-rename                 | Semantic-convention renames are proposals, not automatic edits                                                                                                                                                                                                                                                                        |
| One tracing stack                       | Final state cannot keep legacy Zipkin/OpenTracing/Jaeger as active stack                                                                                                                                                                                                                                                              |
| One instrumentation mechanism           | Register each library once, through one path: the `auto-instrumentations-node/register` launcher, **or** `NodeSDK({ instrumentations })`, **or** a standalone `registerInstrumentations()` — never two for the same library, because double instrumentation can duplicate spans. `@fastify/otel` is a plugin the launcher never wires |
| One propagator registration             | Set the propagator once, as `textMapPropagator` on the SDK. `@opentelemetry/api` refuses a duplicate global registration, so a `setGlobalPropagator()` call after `sdk.start()` returns `false`, logs `Attempted duplicate registration of API: propagation`, and silently changes nothing                                            |
| `fetch()` needs its own instrumentation | Node's global `fetch` is undici, not the `http` module: without `@opentelemetry/instrumentation-undici` there is no client span **and no trace headers on the wire**, so every downstream service starts a new root trace while this service's own spans look correct                                                                 |
| Load tracing first                      | The tracing bootstrap must initialize before any instrumented module is imported; ESM `import` hoisting or a bundler that inlines requires silently defeats monkey-patch instrumentation                                                                                                                                              |
| Correct OTLP encoding                   | `http/protobuf` = `@opentelemetry/exporter-trace-otlp-proto`; `-otlp-http` ships JSON, `-otlp-grpc` ships gRPC — picking the wrong package silently breaks the contract format                                                                                                                                                        |
| Sampling & propagation mandatory        | Validation fails if unknown or unverified                                                                                                                                                                                                                                                                                             |
| Defer versions                          | Read versions from `package.json`/lockfile, never hardcode versions in skill text                                                                                                                                                                                                                                                     |
| Sync docs on L4                         | If L4 changes config/env/deps, update service docs in the same pass                                                                                                                                                                                                                                                                   |
| Fresh post-L4 build                     | Runtime pass requires a post-L4 clean install (frozen when a lockfile is committed, refreshed first because L4 changed the manifest), the build check the repository actually has (`tsc` on TypeScript, the bootstrap smoke run on plain JavaScript), and image provenance                                                            |
| End-to-end only when stand is healthy   | Runtime `pass` needs stand health + log triage before Jaeger (§3.4; common L5)                                                                                                                                                                                                                                                        |
| No Jaeger-first pass                    | Jaeger spans while SUT crash-loops or not Ready are not end-to-end pass — fix the stand first                                                                                                                                                                                                                                         |

## 6. File index

- Layers: [`models/`](models/) — L1 discovery, the TypeScript L4 framework gate, and the L5 TypeScript delta
  (L2 and L3 are common)
- Schema: [`schemas/L1-discovery-result.schema.json`](schemas/L1-discovery-result.schema.json)
- Detection signatures: [`reference/detection-rules.md`](reference/detection-rules.md)
- Framework coverage: [`reference/framework-coverage.md`](reference/framework-coverage.md)
- Build blockers (TypeScript delta): [`reference/build-preconditions.md`](reference/build-preconditions.md)
- Runtime install discovery (TypeScript delta): [`reference/service-installation-discovery.md`](reference/service-installation-discovery.md)
- Recipes: [`recipes/`](recipes/) — L4 apply, `fresh-build-and-image`, and the `validation-stack` delta
- Shared core: [`opentelemetry-tracing-common/SKILL.md`](../opentelemetry-tracing-common/SKILL.md)
