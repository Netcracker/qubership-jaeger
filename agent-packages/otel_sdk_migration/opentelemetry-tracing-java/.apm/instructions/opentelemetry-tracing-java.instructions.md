---
description: Trigger for auditing or migrating distributed tracing in a Java service.
applyTo: "**/{*.java,*.kt,pom.xml,build.gradle,build.gradle.kts}"
---

# OpenTelemetry tracing (Java)

When auditing, enabling, or migrating distributed tracing in a Java service — its spans, propagators, sampling,
OTLP export, `TRACING_*` values, or `traceId`/`spanId` log correlation — apply the `opentelemetry-tracing-java` skill.
The user does not need to name it.
