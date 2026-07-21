# Recipe — configuration migration (Go)

Concrete mappings for Layer 4 §4.2 (`configMigration`).

## Source of truth

Contracted parameters, export format, propagation, sampling, and service
naming come from the umbrella platform contract
([`platform-tracing-guide.md`](../../opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md))
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

## Propagation

**The migration preserves the wire format; it does not change it.** Carry the
configured inject format across, raise a conflict with the contract as a
**question** to the user, and on a greenfield service ask the user to pick
`B3` / `B3_MULTI` / `W3C` / a multi-format set instead of choosing silently
(umbrella
[`platform-tracing-guide.md`](../../opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md)
§Propagation).

`OTEL_PROPAGATORS` and programmatic setup are both **runtime** in Go — the
format stays switchable without a rebuild.

### Name the constructor option, not just the format

`b3.New()` with no options injects the **single** `b3` header, not `X-B3-*` —
the default fires an explicit `InjectEncoding == B3Unspecified` fallback that
writes `b3`, while the `X-B3-*` branch has no such fallback. Source coordinates
and the exact mechanism:
[`platform-tracing-guide.md`](../../opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md)
§Verify constructor defaults — verify against the b3 version in the service's
`go.mod`.

A plan row that says "b3multi" and ships `b3.New()` is wrong on the wire while
every end-to-end test still passes.

```go
// B3 multi-header (X-B3-TraceId / X-B3-SpanId) — required for b3multi
otel.SetTextMapPropagator(b3.New(b3.WithInjectEncoding(b3.B3MultipleHeader)))
```

### Composite: extract order matters, inject writes everything

On **extract**, `propagation.NewCompositeTextMapPropagator` gives priority to the
**last** entry — it chains `ctx` through every member, so the last one that finds
a context overwrites the earlier result (`propagation/propagation.go:136-141` in
`go.opentelemetry.io/otel@v1.43.0`). That is the opposite of Spring Boot. Derive
the order yourself from the user's intent ("B3 wins") — do not ask which end
wins, and do not copy a list from a Java service.

On **inject** the composite loops every member (`:130-134`), so both formats
below are written to each outgoing request. Order does not apply, and there is
no way to emit only one without a custom `TextMapPropagator`.

```go
// extract: accepts traceparent and X-B3-*; B3 wins when both arrive (it is last)
// inject:  writes traceparent AND X-B3-* on every outgoing request
otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(
    propagation.TraceContext{},
    b3.New(b3.WithInjectEncoding(b3.B3MultipleHeader)),
))
```

Multi-format is a valid target and needs nothing extra around it — the
assumption is that adjacent tooling does not overwrite an existing context.

## Legacy config mappings

| From                    | To                                            | 1:1     |
|-------------------------|-----------------------------------------------|---------|
| `tracing.host`          | `TRACING_HOST` + OTLP endpoint composition    | no      |
| `tracing.enabled`       | `TRACING_ENABLED`                             | yes     |
| `tracing.sampler.const` | `TRACING_SAMPLER_CONST` or probabilistic path | partial |
| hardcoded Zipkin URL    | OTLP endpoint from `TRACING_HOST`             | no      |

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

`OTEL_PROPAGATORS=b3multi` above is the **contract default**, used only when the
service has no format configured and the user chose it. An existing format is
preserved instead — see §Propagation.

For wrapper-based services, mapped runtime behavior can be implemented through
wrapper options, but final behavior must match this shape.
