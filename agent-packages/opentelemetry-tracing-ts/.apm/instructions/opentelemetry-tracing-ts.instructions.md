---
description: Audits and migrates TypeScript/Node distributed tracing to OpenTelemetry (maturity 1-5, migration + validation plan) for Qubership services. Apply on tracing, legacy stacks, OTel migration, TRACING_* / OTLP / propagation / log correlation tasks — user does not need to name the skill. Covers ESM/bundler import-order breakage and worker_threads/child_process context loss.
applyTo: "**/{*.ts,*.tsx,*.mts,*.cts,*.js,*.mjs,*.cjs,*.json,*.yml,*.yaml,*.tpl,Dockerfile,Dockerfile.*,*.Dockerfile,.env,.env.*}"
---

# OpenTelemetry tracing (TypeScript / Node)

When auditing or changing distributed tracing in a TypeScript or Node service —
assessing maturity, detecting legacy stacks (Zipkin, Jaeger client, OpenTracing),
hybrid or incomplete OpenTelemetry, broken OTLP export, ESM/bundler and
import-order breakage, worker_threads/child_process/Kafka context loss,
`TRACING_*` / Helm tracing values, sampling, propagators, or `traceId`/`spanId`
log correlation — apply the `opentelemetry-tracing-ts` skill. The user does
**not** need to name the skill; triggers include plain mentions of tracing,
spans, Jaeger, OpenTelemetry, or missing/broken traces.

Pipeline gates (Phase 1/2 split, multi-language scope gate, stand health gate,
platform conventions) are shared — see the `opentelemetry-tracing-common`
instruction.
