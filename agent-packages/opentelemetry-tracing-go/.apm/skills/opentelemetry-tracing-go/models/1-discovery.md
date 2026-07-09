# Layer 1 — Discovery (Go)

**Goal:** enumerate every existing element of tracing implementation.
Discovery reports what exists, not whether it works.

- **Input:** repository root (Go source, `go.mod`, config, deployment, Helm/k8s).
- **Output:** `discovery-result.json` validated by
  [`../schemas/L1-discovery-result.schema.json`](../schemas/L1-discovery-result.schema.json).
- **Detection signatures:** [`../reference/detection-rules.md`](../reference/detection-rules.md).

Run sections **1.0–1.6**; emit every required JSON object. Missing evidence →
`unknown` or empty arrays per schema; record why in `gaps` — do not omit sections.

## 1.0 Framework discovery

Set `service.framework` (schema enum) and optional `service.name`:

| Framework         | Typical evidence                                                                                 |
|-------------------|--------------------------------------------------------------------------------------------------|
| `cloudcore-fiber` | Fiber HTTP stack with org/platform server wrapper + `WithTracer(...)` (see `detection-rules.md`) |
| `net-http`        | stdlib `net/http` server, no Fiber/Gin/Echo router                                               |
| `gin`             | `gin-gonic/gin`                                                                                  |
| `echo`            | `labstack/echo`                                                                                  |
| `pure-go`         | OTel wired without the frameworks above                                                          |
| `unknown`         | insufficient evidence — note in `gaps`                                                           |

## 1.1 Dependency discovery

Inputs:

- `go.mod`, `go.sum`, `vendor/`, workspace files;
- optional `go list -m all` or equivalent dependency graph command.

Classify tracing artifacts into buckets:

- **legacy**: `openzipkin/zipkin-go`, `opentracing/opentracing-go`, `jaeger-client-go`, vendor/platform Zipkin tracer wrappers (catalogue in `detection-rules.md`);
- **modern**: `go.opentelemetry.io/otel*`, OTLP exporters, B3 propagator module.

Set aggregate flags:

- `hasOtelApi`
- `hasOtelSdk`
- `hasExporter`
- `hasLegacy`

## 1.2 Configuration discovery

Inspect config/env locations:

- `.env`, Helm values/templates, Deployment env vars;
- app config loaders (`koanf`, `viper`, env/yaml/struct-based project loaders);
- hardcoded tracing constants in Go files.

Collect:

- export endpoint/protocol/target guess;
- propagation formats and per-component wiring (HTTP/Kafka/async);
- sampler type and ratio.

## 1.3 API discovery (AST/symbol)

Find symbols:

- OTel: `otel.Tracer`, `tracer.Start`, `trace.SpanFromContext`,
  `propagation.TextMapPropagator`, `otel.SetTracerProvider`;
- legacy: Zipkin/OpenTracing/Jaeger client symbols;
- vendor/platform tracing wrappers (e.g. `NewZipkinTracer`, `WithTracer(...)`) —
  signatures in `detection-rules.md`;

Record `family`, `symbol`, `file`, `line`.

## 1.4 Instrumentation discovery

Classify `instrumentation.mode`:

- `auto`: no explicit spans but framework/wrapper auto instrumentation evidence;
- `manual`: explicit span creation in app code;
- `mixed`: both;
- `none`: no evidence.

## 1.5 Async-boundary discovery

Detect context-loss candidates:

- goroutines (`go func(...)`), worker pools/channels;
- Kafka producers/consumers (`segmentio/kafka-go`, Sarama, other messaging libs in `go.mod`);
- async HTTP clients and callback-style execution.

Mark `contextWrapper` true only when context is explicitly propagated.

## 1.6 Platform-contract discovery

Collect mandatory contract evidence:

- `TRACING_ENABLED`, `TRACING_HOST`, `TRACING_SAMPLER_*`;
- OTLP `http/protobuf` path and host alias;
- `b3multi` propagation;
- `parentbased_traceidratio` or equivalent parent-based ratio behavior;
- `service.name=${name}-${namespace}` and namespace source
  (Downward API/Helm/SA file);
- excluded probe/metrics endpoints;
- `traceId`/`spanId` in log output.

For missing inspectable evidence, use `unknown` and record `gaps`.

## User-facing brief (mandatory)

After `discovery-result.json`, post the **L1 Discovery brief** in chat per
[`../SKILL.md`](../SKILL.md) §3.1 (5–10 bullets: framework, dependencies, config,
instrumentation, async boundaries, platform gaps). Do not proceed to L2 until posted.
