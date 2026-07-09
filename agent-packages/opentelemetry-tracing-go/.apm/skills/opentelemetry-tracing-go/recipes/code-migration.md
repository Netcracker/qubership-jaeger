# Recipe — code migration (Go)

Concrete API rewrites for Layer 4 §4.3 (`codeMigration`).

Mechanical rewrites can be applied when safe; semantic attribute renames are
proposal-only.

## Legacy -> OTel examples

### OpenTracing span lifecycle -> OTel

```go
// before
span := opentracing.StartSpan("operation")
defer span.Finish()

// after
ctx, span := tracer.Start(ctx, "operation")
defer span.End()
```

### Zipkin wrapper path

```go
// before
app := fiberserver.New().WithTracer(tracing.NewZipkinTracer()).Process()

// after (conceptual)
tp := buildOtelProviderFromEnv()
otel.SetTracerProvider(tp)
app := fiberserver.New().WithTracer(buildOtelExporterAdapter(tp)).Process()
```

Decide the wrapper path in this order:

1. **Check the wrapper first.** Inspect the platform wrapper library used by the
   service (current version in `go.mod` and newer released versions) for an
   OTLP-capable tracer/exporter option. If one exists, upgrade/configure the
   wrapper — do not build a parallel provider.
2. **Wrapper has no OTLP path** (only a Zipkin factory such as
   `NewZipkinTracer`) — build a local `TracerProvider` (OTLP HTTP exporter +
   B3 Multi propagator + `parentbased_traceidratio` sampler wired to platform
   env) and hand it to the wrapper via its tracer injection point
   (e.g. `WithTracer(...)`), keeping wrapper middleware for span creation.

Either way the final active export path must be OTLP `http/protobuf` toward
`TRACING_HOST` — never the wrapper's legacy Zipkin endpoint.

### OTLP HTTP exporter wiring (Go SDK)

The Go OTLP HTTP exporter takes endpoint and path **separately** — a scheme in
the endpoint or a missing signal path causes 404s or silent export failure:

```go
exp, err := otlptracehttp.New(ctx,
    // host:port only — no "http://" scheme
    otlptracehttp.WithEndpoint(net.JoinHostPort(tracingHost, "4318")),
    otlptracehttp.WithURLPath("/v1/traces"),
    // platform proxy speaks plain HTTP in-cluster
    otlptracehttp.WithInsecure(),
)
```

Use `WithEndpointURL` only if the full URL (scheme + host + path) is composed
in one place; do not mix it with `WithEndpoint`/`WithURLPath`.

## Mechanical rewrite table

| Rule ID                     | Before                  | After                              |
|-----------------------------|-------------------------|------------------------------------|
| `startspan-to-tracer-start` | `opentracing.StartSpan` | `tracer.Start(ctx, name)`          |
| `finish-to-end`             | `span.Finish()`         | `span.End()`                       |
| `zipkin-wrapper-to-otel`    | `NewZipkinTracer`       | OTel provider/exporter wiring      |
| `globaltracer-to-context`   | global span usage       | context-based tracer/span handling |

## Guardrails

- Keep one active tracing stack.
- Preserve business/service naming intent.
- Never write secrets or unbounded payloads to span attributes.
