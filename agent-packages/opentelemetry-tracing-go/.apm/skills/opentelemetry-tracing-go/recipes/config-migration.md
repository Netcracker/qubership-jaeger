# Recipe — configuration migration (Go)

Concrete mappings for Layer 4 §4.2 (`configMigration`).

## Source of truth

Contracted parameters, export format, propagation, sampling, and service
naming come from the umbrella platform contract
([`platform-tracing-guide.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md))
— do not restate or override them here.

### Service name and namespace (Go pitfall)

Go-specific pitfall: low-level config readers (e.g. `koanf` `MustString`) return
YAML placeholders like `${NAMESPACE:unknown}` **verbatim** — the exported
service name then literally contains the placeholder. Build `service.name` from
resolved values only: read the namespace env var (`NAMESPACE` /
`MICROSERVICE_NAMESPACE` injected via Downward API or deployer), use a config
loader that merges env over file, or read the serviceaccount namespace file.
Verify the resolved value at startup — never ship a literal `${...}` into the
resource attributes.

## Legacy config mappings

| From                    | To                                            | 1:1     |
|-------------------------|-----------------------------------------------|---------|
| `tracing.host`          | `TRACING_HOST` + OTLP endpoint composition    | no      |
| `tracing.enabled`       | `TRACING_ENABLED`                             | yes     |
| `tracing.sampler.const` | `TRACING_SAMPLER_CONST` or probabilistic path | partial |
| hard-coded Zipkin URL   | OTLP endpoint from `TRACING_HOST`             | no      |

## Required target env shape

```text
TRACING_ENABLED=true|false
TRACING_HOST=nc-diagnostic-agent
TRACING_SAMPLER_PROBABILISTIC=0.01
OTEL_EXPORTER_OTLP_ENDPOINT=http://${TRACING_HOST}:4318/v1/traces
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_PROPAGATORS=b3multi
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=${TRACING_SAMPLER_PROBABILISTIC}
OTEL_SERVICE_NAME=${MICROSERVICE_NAME}-${NAMESPACE}
```

For wrapper-based services, mapped runtime behavior can be implemented through
wrapper options, but final behavior must match this shape.
