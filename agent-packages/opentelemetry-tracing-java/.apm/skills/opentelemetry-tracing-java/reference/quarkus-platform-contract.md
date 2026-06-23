# Quarkus — platform contract wiring

Applies to every Java service on **`quarkus-opentelemetry`** (native extension), not
to Spring Boot or the OTel Java agent. Grounded in the platform `TRACING_*`
contract and Quarkus OTel configuration model.

## Do not mirror the Spring Boot SpEL toggle

Spring Boot uses a SpEL-driven `otel.sdk.disabled` toggle that reacts to
`TRACING_ENABLED` at runtime. A common Quarkus mistake copies that idea with
nested keys:

```properties
tracing.sdk.disabled.true=false
tracing.sdk.disabled.false=true
quarkus.otel.sdk.disabled=${tracing.sdk.disabled.${TRACING_ENABLED:false}}
```

**This pattern is unreliable on Quarkus.** Setting only `TRACING_ENABLED=true` in
Kubernetes/Helm often leaves the SDK off: nested SmallRye Config expansion does
not behave like Spring SpEL, and pre-built images are usually compiled with
`TRACING_ENABLED` unset (default `false`).

### Runtime enable (validation and production)

When tracing must be turned on at deploy time without a rebuild, set explicit
Quarkus env vars alongside platform keys:

```text
TRACING_ENABLED=true
TRACING_HOST=nc-diagnostic-agent
TRACING_SAMPLER_PROBABILISTIC=1.0

QUARKUS_OTEL_SDK_DISABLED=false
QUARKUS_OTEL_EXPORTER_OTLP_ENDPOINT=http://nc-diagnostic-agent:4318
```

`quarkus.otel.sdk.disabled` is **runtime**-configurable in Quarkus
(`QUARKUS_OTEL_SDK_DISABLED`); use it directly instead of the nested toggle.

Preferred long-term config shapes (pick one):

1. **Helm/K8s env** — map `TRACING_ENABLED` → `QUARKUS_OTEL_SDK_DISABLED` in the
   chart (`false` when enabled, `true` when disabled).
2. **application.properties** — bind directly, e.g.
   `quarkus.otel.sdk.disabled=${QUARKUS_OTEL_SDK_DISABLED:true}` with the chart
   setting `QUARKUS_OTEL_SDK_DISABLED=false` when tracing is on.
3. **Build per environment** — only if the org accepts separate images; not the
   default for platform services.

Record nested-toggle configs in discovery as **high risk** until verified with a
runtime deploy.

## OTLP endpoint — base URL, not platform path suffix

Platform contract logical target:

`http://${TRACING_HOST}:4318/v1/traces` (OTLP `http/protobuf`).

For **Quarkus** `quarkus.otel.exporter.otlp.endpoint` (and
`QUARKUS_OTEL_EXPORTER_OTLP_ENDPOINT`), use the **base URL without**
`/v1/traces`:

```properties
quarkus.otel.exporter.otlp.endpoint=http://${TRACING_HOST:nc-diagnostic-agent}:4318
quarkus.otel.exporter.otlp.protocol=http/protobuf
```

Quarkus appends the signal path (`v1/traces`) for `http/protobuf`. Putting
`/v1/traces` in the property can produce a double path and silent export failure.

| Surface                         | Value                                      |
|---------------------------------|--------------------------------------------|
| Platform / Helm docs            | `http://${TRACING_HOST}:4318/v1/traces`    |
| Quarkus `quarkus.otel.*`        | `http://${TRACING_HOST}:4318`              |
| Runtime override env            | `QUARKUS_OTEL_EXPORTER_OTLP_ENDPOINT=http://…:4318` |

## Build-time vs runtime (single image, many environments)

Quarkus OpenTelemetry splits properties:

| Property / area                         | Build-time fixed? | Runtime toggle note                                      |
|-----------------------------------------|-------------------|----------------------------------------------------------|
| `quarkus.otel.sdk.disabled`             | no (runtime)      | use for on/off export                                    |
| `quarkus.otel.exporter.otlp.enabled`    | yes               | cannot re-enable export at runtime via this flag         |
| `quarkus.otel.traces.exporter` = `none` | yes               | disables trace export in the built artifact              |
| `quarkus.otel.traces.sampler`           | often build-time  | use `quarkus.otel.traces.sampler.arg` at runtime for ratio |
| Sampler ratio off without SDK disable   | —                 | set `sampler.arg=0` per Quarkus docs (keeps propagation) |

If L5 validation shows **no services in Jaeger** while `opentelemetry` is in
installed features, check in order:

1. `QUARKUS_OTEL_SDK_DISABLED` / nested toggle (SDK still off).
2. OTLP endpoint shape (base URL vs `/v1/traces` suffix).
3. Traffic on a path **not** in `quarkus.otel.traces.suppress-application-uris`.
4. Collector reachability from the pod (`TRACING_HOST` service on `:4318`).

## Related

- Mechanism guardrails (extension only, no javaagent):
  [`../models/4-transformation.md`](../models/4-transformation.md)
- Runtime validation stack:
  [`../recipes/validation-stack.md`](../recipes/validation-stack.md)
- Config mappings:
  [`../recipes/config-migration.md`](../recipes/config-migration.md)
