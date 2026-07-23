# Detection rules (Go)

Layer 1 signature catalogue for Go services.

## Dependency signatures (`go.mod`)

| Module path                                                             | Bucket | Technology               |
|-------------------------------------------------------------------------|--------|--------------------------|
| `github.com/openzipkin/zipkin-go`                                       | legacy | zipkin                   |
| `github.com/opentracing/opentracing-go`                                 | legacy | opentracing              |
| `github.com/uber/jaeger-client-go`                                      | legacy | jaeger-client            |
| `go.opentelemetry.io/otel`                                              | modern | otel-api                 |
| `go.opentelemetry.io/otel/sdk`                                          | modern | otel-sdk                 |
| `go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp`       | modern | otel-exporter            |
| `go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc`       | modern | otel-exporter            |
| `go.opentelemetry.io/contrib/propagators/b3`                            | modern | otel-propagator          |
| `go.opentelemetry.io/contrib/instrumentation/*`                         | modern | otel-instrumentation     |
| `github.com/netcracker/qubership-core-lib-go-actuator-common/*/tracing` | legacy | cloudcore-zipkin-wrapper |

Aggregate flags:

- `hasOtelApi`: OTel API module present.
- `hasOtelSdk`: OTel SDK module present.
- `hasExporter`: OTLP/Zipkin exporter module or wrapper exporter present.
- `hasLegacy`: legacy tracer stack wired (not just transitive).

## Configuration signatures

Platform-level keys (from the common platform contract):

- `TRACING_ENABLED`
- `TRACING_HOST` (default `nc-diagnostic-agent`)
- `TRACING_SAMPLER_RATELIMITING`
- `TRACING_SAMPLER_PROBABILISTIC`
- `TRACING_SAMPLER_CONST`

OTel keys:

- `OTEL_EXPORTER_OTLP_ENDPOINT`
- `OTEL_EXPORTER_OTLP_PROTOCOL` (`http/protobuf` expected)
- `OTEL_PROPAGATORS` (contract default `b3multi`; runtime scope — drives inject
  and extract; an already-configured format is preserved, not replaced)
- `OTEL_TRACES_SAMPLER`
- `OTEL_TRACES_SAMPLER_ARG`
- `OTEL_SERVICE_NAME`

Legacy/wrapper keys:

- `tracing.enabled`
- `tracing.host`
- `tracing.sampler.const`
- `tracing.sampler.ratelimiting`
- `microservice.name`

## Code signatures

OTel:

- `otel.SetTracerProvider`
- `otel.Tracer(...)`
- `tracer.Start(...)`
- `trace.SpanFromContext(...)`
- `propagation.TraceContext` / `b3.New` — read the **options**: bare `b3.New()`
  injects single `b3`, `X-B3-*` needs `b3.WithInjectEncoding(b3.B3MultipleHeader)`
- `otel.SetTextMapPropagator` / `propagation.NewCompositeTextMapPropagator` —
  composite priority is the **last** entry
- `otlptracehttp.New(...)` / `otlptracegrpc.New(...)`

Legacy:

- `zipkin.NewTracer`
- `opentracing.GlobalTracer()`
- `jaeger.NewTracer`

Platform/vendor HTTP tracing wrapper:

- `tracing.NewZipkinTracer(...)`
- `tracing.NewZipkinTracerWithOpts(...)`
- `WithTracer(...)`

## Instrumentation mode signatures

| Evidence                                   | Mode   |
|--------------------------------------------|--------|
| Wrapper/middleware only, no explicit spans | auto   |
| Explicit `tracer.Start` in app code        | manual |
| Both wrapper auto path and explicit spans  | mixed  |
| No symbols from table                      | none   |

## Async-boundary signatures

| Symbol/pattern                                       | Boundary type                   |
|------------------------------------------------------|---------------------------------|
| `go func(...)`                                       | goroutine                       |
| channels (`chan`, `<-`)                              | channel                         |
| worker pool loops                                    | worker-pool                     |
| `kafka-go` writer/reader or Sarama producer/consumer | kafka-producer / kafka-consumer |
| outbound HTTP in async worker                        | http-client                     |

Mark boundary as context-loss candidate when no `context.Context` propagation is
visible.

## Platform-contract signatures

Map to mandatory checks:

- `service.name=${name}-${namespace}` or equivalent runtime construction;
- namespace source via Downward API, Helm `.Release.Namespace`, or serviceaccount file;
- OTLP endpoint `http://${TRACING_HOST}:4318/v1/traces` (or equivalent host+path composition);
- propagation `b3multi` (or explicitly documented compatible format);
- sampler uses parent-based ratio behavior in production (`parentbased_traceidratio`);
- probe/metrics endpoint exclusions (`/health*`, `/metrics`, `/prometheus`, `/q/*`, `/actuator/*`);
- log format includes `traceId` and `spanId`.
