---
description: Trigger for auditing or migrating distributed tracing in a TypeScript or Node service.
applyTo: "**/{*.ts,*.tsx,*.mts,*.cts,package.json}"
---

When auditing, enabling, or migrating distributed tracing in a TypeScript or Node service — its spans, propagators,
sampling, OTLP export, `TRACING_*` values, `traceId`/`spanId` log correlation, or the bootstrap load order that
decides whether instrumentation runs at all — apply the `opentelemetry-tracing-ts` skill. The user does not need to
name it.
