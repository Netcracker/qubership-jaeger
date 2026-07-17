# Recipe — dependency migration (Go)

Concrete moves for Layer 4 §4.1 (`dependencyMigration`) — see umbrella
[`models/4-transformation.md`](../../opentelemetry-tracing-umbrella/models/4-transformation.md)
§4.1.

Read versions from target `go.mod`; do not hardcode versions here.

**Prerequisite:** complete Go [`models/4-transformation.md`](../models/4-transformation.md)
Step 0 (framework stack) before emitting §4.1 rows — dependency moves follow
`discovery-result.service.framework`, not a free choice.

## Framework stack → dependency path

| `service.framework`         | §4.1 focus                                                                            |
|-----------------------------|---------------------------------------------------------------------------------------|
| `cloudcore-fiber`           | platform HTTP wrapper modules + OTel SDK baseline (wrapper upgrade or inject — below) |
| `net-http`, `pure-go`       | OTel SDK baseline modules only                                                        |
| `gin`, `echo`, other router | baseline + router OTel middleware module discovered in `go.mod`                       |
| `unknown`                   | conservative baseline; record assumptions in `gaps`                                   |

Wrapper and router detection signatures:
[`reference/detection-rules.md`](../reference/detection-rules.md).

## Source-of-truth constraints

From the umbrella platform contract
([`platform-tracing-guide.md`](../../opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md)):

- preferred client library: OpenTelemetry SDK for Go;
- wrappers are allowed only if they preserve platform requirements;
- Jaeger/OpenTracing client libraries are retired migration targets;
- OTLP is the recommended export format.

## Legacy → OTel moves

### Zipkin/OpenTracing/Jaeger client stacks

Applies to every framework stack when these are the active tracing dependencies:

- remove: `openzipkin/zipkin-go`, `opentracing/opentracing-go`, `jaeger-client-go` (when active stack).
- add: `go.opentelemetry.io/otel`, `go.opentelemetry.io/otel/sdk`,
  OTLP exporter module, B3 propagator module.

### Platform/vendor HTTP wrapper (`cloudcore-fiber` and similar)

When Step 0 selected a **Fiber + platform HTTP wrapper** stack (schema value `cloudcore-fiber`, or wrapper
symbols such as `NewZipkinTracer`, `WithTracer` in `detection-rules.md`):

1. check the wrapper library first — current and newer released versions may
   already ship an OTLP-capable exporter option; prefer upgrading the wrapper
   over replacing it;
2. migrate wrapper configuration to platform env (`TRACING_*`);
3. ensure exporter path ends at OTLP `http/protobuf` endpoint via `TRACING_HOST`;
4. if no wrapper version provides an OTLP path, keep the wrapper middleware but
   inject an explicit OTel SDK `TracerProvider` (see
   [`code-migration.md`](code-migration.md)), or replace with explicit OTel SDK
   setup.

Do not keep wrapper Zipkin export as final active path.

For `gin` / `echo` / other router stacks, add the router's OTel middleware
module from discovery — do not duplicate wrapper steps above.

## Target baseline modules

Required for `net-http`, `pure-go`, and as the SDK foundation for wrapper/router paths:

- `go.opentelemetry.io/otel`
- `go.opentelemetry.io/otel/sdk`
- `go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp`
- `go.opentelemetry.io/contrib/propagators/b3`

Use `otlptracegrpc` only when environment explicitly requires gRPC OTLP.

## Module-graph guardrails

After adding OTel SDK modules to `go.mod`, run `go build ./...` and check for
`ambiguous import` errors on `google.golang.org/genproto`: gRPC and platform
libraries often pin the old monolithic `genproto` module while OTel pulls the
split `google.golang.org/genproto/googleapis/*` modules. Resolve by pinning or
excluding the conflicting `genproto` versions in `go.mod` (align on the split
modules); record the resolution in the migration plan.
