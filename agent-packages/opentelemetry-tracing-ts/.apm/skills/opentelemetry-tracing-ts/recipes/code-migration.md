# Recipe — code migration (TypeScript / Node)

Concrete API rewrites for Layer 4 §4.3 (`codeMigration`).

Mechanical rewrites can be applied when safe; semantic attribute renames are proposal-only.

## Bootstrap — SDK setup (loaded first; see config-migration.md §Load order)

```ts
// tracing.ts — imported/required BEFORE the app entrypoint
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-proto'; // http/protobuf
import { B3Propagator, B3InjectEncoding } from '@opentelemetry/propagator-b3';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';

const sdk = new NodeSDK({
  resource: resourceFromAttributes({
    [ATTR_SERVICE_NAME]: `${process.env.MICROSERVICE_NAME}-${process.env.NAMESPACE}`,
  }),
  traceExporter: new OTLPTraceExporter(), // endpoint/protocol from OTEL_EXPORTER_OTLP_* env
  textMapPropagator: new B3Propagator({ injectEncoding: B3InjectEncoding.MULTI_HEADER }),
  // instrumentations: [...] // Step 0b: launcher XOR programmatic — not both for one lib
});
sdk.start();
```

`NodeSDK` registers the `AsyncLocalStorageContextManager` so context follows
`await`, and wires a `BatchSpanProcessor` around `traceExporter` for you. Sampler
and propagator can come from `OTEL_*` env instead of code.

**API version note (verify against the manifest).** `resourceFromAttributes` /
`ATTR_SERVICE_NAME` are the current names; older `@opentelemetry/resources` uses
`new Resource({ [SemanticResourceAttributes.SERVICE_NAME]: ... })`. On the manual
`NodeTracerProvider` path (instead of `NodeSDK`) you must add the span processor
yourself — recent versions take `new NodeTracerProvider({ spanProcessors: [new BatchSpanProcessor(exporter)] })`,
older ones use `provider.addSpanProcessor(...)`. Pick the shape that matches the
installed version rather than hardcoding one.

## Legacy → OTel examples

### OpenTracing span lifecycle → OTel

```ts
// before
const span = opentracing.globalTracer().startSpan('operation');
try {
  // ...
} finally {
  span.finish();
}

// after
import { trace } from '@opentelemetry/api';
const tracer = trace.getTracer('my-service');
await tracer.startActiveSpan('operation', async (span) => {
  try {
    // ...
  } finally {
    span.end();
  }
});
```

### jaeger-client / zipkin setup → OTel SDK + OTLP

```ts
// before — jaeger-client (udp/thrift to the agent)
import { initTracer } from 'jaeger-client';
const tracer = initTracer(config, options);

// after — OTel SDK exporting OTLP http/protobuf to the platform proxy
// see the bootstrap above (NodeSDK + OTLPTraceExporter from -otlp-proto)
```

The exporter reads `OTEL_EXPORTER_OTLP_*` from the environment — keep endpoint and
protocol in config, not hardcoded (see [`config-migration.md`](config-migration.md)).

### Framework instrumentation (`sdk` mechanism)

```ts
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { HttpInstrumentation } from '@opentelemetry/instrumentation-http';
import { ExpressInstrumentation } from '@opentelemetry/instrumentation-express';

registerInstrumentations({
  instrumentations: [new HttpInstrumentation(), new ExpressInstrumentation()],
});
```

Do **not** combine this with the `@opentelemetry/auto-instrumentations-node/register`
launcher for the same app — pick one mechanism (Step 0b in
[`../models/4-transformation.md`](../models/4-transformation.md)). NestJS also needs
`@opentelemetry/instrumentation-nestjs-core` plus the adapter (`-express`/`-fastify`).

## Mechanical rewrite table

| Rule ID                    | Before                              | After                                                    |
|----------------------------|-------------------------------------|----------------------------------------------------------|
| `startspan-to-tracer`      | `opentracing…startSpan(name)`       | `tracer.startActiveSpan(name, cb)` (activates context)   |
| `finish-to-end`            | `span.finish()`                     | `span.end()`                                             |
| `set-tag-to-set-attribute` | `span.setTag(k, v)`                 | `span.setAttribute(k, v)`                                |
| `jaeger-client-to-otel`    | `initTracer(...)`                   | `NodeSDK` + OTLP proto exporter                          |
| `global-tracer-to-context` | `opentracing.globalTracer()` use    | `trace.getTracer(name)` + `trace.getActiveSpan()`        |

## Semantic renames (proposal-only)

Attribute renames toward OpenTelemetry semantic conventions (e.g. custom
`http_path` → `http.route`, business keys) are **never** auto-applied. List them in
`codeMigration.semantic` and ask for confirmation (common
[`models/4-transformation.md`](../../opentelemetry-tracing-common/models/4-transformation.md)
§4.3).

## Guardrails

- Keep one active tracing stack.
- Preserve business/service naming intent.
- Never write secrets or unbounded payloads to span attributes.
- Prefer `startActiveSpan` (activates the span in context) over `startSpan`
  (creates a detached span you must pass manually) unless you deliberately manage
  context yourself.
