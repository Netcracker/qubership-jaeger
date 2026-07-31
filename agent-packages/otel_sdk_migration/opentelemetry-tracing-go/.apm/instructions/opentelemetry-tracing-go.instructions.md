---
description: Audits and migrates Go distributed tracing to OpenTelemetry (maturity 1-5, migration + validation plan) for Qubership services. Apply on tracing, legacy stacks, OTel migration, TRACING_* / OTLP / propagation / log correlation tasks — user does not need to name the skill.
applyTo: "**/{*.go,*.mod,*.sum,*.yml,*.yaml,*.tpl,Dockerfile,Dockerfile.*,*.Dockerfile,.env,.env.*}"
---

# OpenTelemetry tracing (Go)

When auditing or changing distributed tracing in a Go service — assessing
maturity, detecting legacy stacks (Zipkin, Jaeger client, OpenTracing),
hybrid or incomplete OpenTelemetry, broken OTLP export, Kafka/async
context loss, `TRACING_*` / Helm tracing values, sampling, propagators, or
`traceId`/`spanId` log correlation — apply the `opentelemetry-tracing-go`
skill. The user does **not** need to name the skill; triggers include plain
mentions of tracing, spans, Jaeger, OpenTelemetry, or missing/broken traces.

Pipeline gates (Phase 1/2 split, multi-language scope gate, stand health gate,
platform conventions) are shared — see the `opentelemetry-tracing-common`
instruction.
