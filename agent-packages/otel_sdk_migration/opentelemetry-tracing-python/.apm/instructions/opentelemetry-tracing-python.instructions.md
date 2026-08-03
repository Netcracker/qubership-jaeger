---
description: Trigger for auditing or migrating distributed tracing in a Python service.
applyTo: "**/{*.py,pyproject.toml,requirements.txt,requirements-*.txt}"
---

When auditing, enabling, or migrating distributed tracing in a Python service — its spans, propagators, sampling,
OTLP export, `TRACING_*` values, or `traceId`/`spanId` log correlation — apply the `opentelemetry-tracing-python`
skill. The user does not need to name it.
