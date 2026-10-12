# Recipe — runtime validation stack — Java delta

Preconditions, topology, platform env, minimal install, runtime order, and teardown:
[`opentelemetry-tracing-common/recipes/validation-stack.md`](../../opentelemetry-tracing-common/recipes/validation-stack.md).

Java specifics below.

## Probe sizing on the JVM

Size the probes to the **real** start time. JVM services commonly need minutes, not seconds, to pass readiness, and an
aggressive `livenessProbe` kills the pod mid-startup and masks the real result. Prefer a `startupProbe`, or generous
`initialDelaySeconds`, over tight liveness.

## Quarkus env exception

For **Quarkus** services running on a pre-built image, platform env alone is not enough — set the runtime env
explicitly as well (see [`../reference/quarkus-platform-contract.md`](../reference/quarkus-platform-contract.md)):

```text
QUARKUS_OTEL_SDK_DISABLED=false
QUARKUS_OTEL_EXPORTER_OTLP_ENDPOINT=http://<proxy-service-name>:4318
```

Nested `${tracing.sdk.disabled.${TRACING_ENABLED}}` toggles copied from Spring often leave the SDK off when only
`TRACING_ENABLED=true` is set.

This is the exception, not the pattern. For Spring Boot and Pure Java, do not redeclare `otel.*` on top of a correctly
built image — the Layer 4 config already turns platform env into the OTLP endpoint, propagation, and sampler.

## No spans in the backend — Java checks first

1. **Quarkus SDK disabled.** `quarkus.otel.sdk.disabled` resolved to `true` through a nested toggle — the two env vars
   above are the fix.
2. **Agent and extension both present.** On Quarkus the runtime `-javaagent` double-instruments and breaks Vert.x;
   remove it ([`../models/4-transformation.md`](../models/4-transformation.md) Step 0b).
3. **Bridge missing on Spring Boot 4.** Without `spring-boot-micrometer-tracing-opentelemetry` and the Boot 4
   `management.tracing.export.*` keys, export is configured but never wired
   ([`dependency-migration.md`](dependency-migration.md)).

Then continue with the shared list.
