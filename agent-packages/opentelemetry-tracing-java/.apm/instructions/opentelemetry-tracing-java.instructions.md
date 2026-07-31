---
description: Audits and migrates Java distributed tracing to OpenTelemetry (maturity 1-5, migration + validation plan) for Qubership services. Apply on tracing, legacy stacks, OTel migration, TRACING_* / OTLP / propagation / log correlation tasks — user does not need to name the skill.
applyTo: "**/{*.java,*.kt,*.xml,*.yml,*.yaml,*.properties,*.gradle,*.kts,Dockerfile,Dockerfile.*,*.Dockerfile,.env,.env.*}"
---

# OpenTelemetry tracing (Java)

When auditing or changing distributed tracing in a Java service — assessing
maturity, detecting legacy stacks (Brave/Zipkin, Jaeger client, OpenTracing,
Sleuth), hybrid or incomplete OpenTelemetry, broken OTLP export, Kafka/async
context loss, `TRACING_*` / Helm tracing values, sampling, propagators, or
`traceId`/`spanId` log correlation — apply the `opentelemetry-tracing-java`
skill. The user does **not** need to name the skill; triggers include plain
mentions of tracing, spans, Jaeger, OpenTelemetry, or missing/broken traces.

Pipeline gates (Phase 1/2 split, multi-language scope gate, stand health gate,
platform conventions) are shared — see the `opentelemetry-tracing-common`
instruction.
