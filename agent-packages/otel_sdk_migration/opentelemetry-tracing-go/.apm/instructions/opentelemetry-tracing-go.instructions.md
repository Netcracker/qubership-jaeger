---
description: Trigger for auditing or migrating distributed tracing in a Go service.
applyTo: "**/{*.go,go.mod}"
---

# OpenTelemetry tracing (Go)

When auditing, enabling, or migrating distributed tracing in a Go service — its spans, propagators, sampling,
OTLP export, `TRACING_*` values, or `traceId`/`spanId` log correlation — apply the `opentelemetry-tracing-go` skill.
The user does not need to name it.
