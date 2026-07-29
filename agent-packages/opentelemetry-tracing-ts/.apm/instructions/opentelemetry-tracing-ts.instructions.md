---
description: Audits and migrates TypeScript/Node distributed tracing to OpenTelemetry (maturity 1-5, migration + validation plan) for Qubership services. Apply on tracing, legacy stacks, OTel migration, TRACING_* / OTLP / propagation / log correlation tasks — user does not need to name the skill.
applyTo: "**/*.{ts,tsx,mts,cts,js,mjs,cjs,json,yml,yaml,tpl,Dockerfile,dockerfile}"
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

Run **Phase 1 (L1–L3) read-only first**: post all three analysis briefs before
any L4 edits, builds, or runtime deploy. If the repository spans **multiple
language families**, ask the user **bulk vs single target** before L4 (common
Multi-language scope gate). Then Phase 2 (L4 + one post-L4 build + validation)
if implementation is in scope.

After runtime deploy, run the **stand health gate** before Jaeger or end-to-end pass/fail
(common `recipes/stand-health-gate.md`). Do not leave validation in a state
where the SUT pod is not Ready or crash-looping.

Prefer Qubership platform conventions (`platform-tracing-guide.md`, OTeC/Jaeger
export, `TRACING_*`) over generic OTel tutorials. Never auto-rename custom
attributes to semantic conventions without confirmation, and never close a tracing
task while sampling or propagation is unknown or unverified.
