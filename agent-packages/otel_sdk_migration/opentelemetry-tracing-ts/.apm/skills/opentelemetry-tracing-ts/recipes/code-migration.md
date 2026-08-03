# Recipe — code migration (TypeScript / Node)

Concrete API rewrites for Layer 4 §4.3 (`codeMigration`).

Mechanical rewrites can be applied when safe; structural rewrites and semantic
attribute renames are proposal-only.

## Bootstrap — SDK setup

Loaded first — see [`config-migration.md`](config-migration.md) §Load order.

```ts
// tracing.ts — imported/required BEFORE the app entrypoint
import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-proto'; // http/protobuf
import { B3Propagator, B3InjectEncoding } from '@opentelemetry/propagator-b3';
import { resourceFromAttributes } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';

// resolve both parts first — a missing env would ship `undefined-undefined`
// as service.name, which passes the "no literal ${...}" check and is still wrong
const serviceName = process.env.MICROSERVICE_NAME;
const namespace = process.env.NAMESPACE; // Downward API, deployer, or the SA file

if (!serviceName || !namespace) {
  console.error('[tracing] disabled: MICROSERVICE_NAME and NAMESPACE must both resolve');
} else {
  const sdk = new NodeSDK({
    resource: resourceFromAttributes({
      [ATTR_SERVICE_NAME]: `${serviceName}-${namespace}`,
    }),
    traceExporter: new OTLPTraceExporter(), // endpoint/protocol from OTEL_EXPORTER_OTLP_* env
    textMapPropagator: new B3Propagator({ injectEncoding: B3InjectEncoding.MULTI_HEADER }),
    // instrumentations: [...] // Step 0b: launcher XOR programmatic — not both for one lib
  });
  sdk.start();

  // BatchSpanProcessor buffers: without this, spans queued at shutdown are dropped
  // on every rolling update and every job exit
  for (const signal of ['SIGTERM', 'SIGINT'] as const) {
    process.on(signal, () => {
      void sdk.shutdown().finally(() => process.exit(0));
    });
  }
}
```

`NodeSDK` registers the `AsyncLocalStorageContextManager` so context follows
`await`, and wires a `BatchSpanProcessor` around `traceExporter` for you. Sampler
and propagator can come from `OTEL_*` env instead of code.

**Set the propagator in exactly one place** — `textMapPropagator` above is that
place, and a `setGlobalPropagator(...)` added after `sdk.start()` is silently
rejected ([`config-migration.md`](config-migration.md) §Propagation).

**API version note (verify against the manifest).** The boundary is the
`@opentelemetry/resources` major. On **2.x** the resource is built with
`resourceFromAttributes({...})`; **1.x** has no such export at all — it is
`new Resource({ [SemanticResourceAttributes.SERVICE_NAME]: ... })`, and the snippet
above fails with `resourceFromAttributes is not a function`. Current
`@opentelemetry/semantic-conventions` ships both `ATTR_SERVICE_NAME` and the legacy
`SemanticResourceAttributes`, so the constant is not the deciding factor — the
resources major is. The same split applies on the manual `NodeTracerProvider` path
(instead of `NodeSDK`), where you add the span processor yourself:
`new NodeTracerProvider({ spanProcessors: [new BatchSpanProcessor(exporter)] })` on
recent versions, `provider.addSpanProcessor(...)` on older ones. Read the installed
majors from the manifest and pick the matching shape — never hardcode one.

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
const tracer = trace.getTracer('orders/checkout'); // instrumentation scope, not the service name
await tracer.startActiveSpan('operation', async (span) => {
  try {
    // ...
  } finally {
    span.end();
  }
});
```

### Error marking → span status

OpenTracing marks failures with a tag and a log event; OTel has a dedicated status
and exception API. Carry both parts across — an exception recorded without the
status leaves the span green.

```ts
// before — OpenTracing
span.setTag('error', true);
span.log({ event: 'error', 'error.object': err });

// after — OTel
import { SpanStatusCode } from '@opentelemetry/api';
span.recordException(err as Error);
span.setStatus({ code: SpanStatusCode.ERROR, message: (err as Error).message });
```

### jaeger-client / zipkin setup → OTel SDK + OTLP

```ts
// before — jaeger-client (udp/thrift to the agent)
import { initTracer } from 'jaeger-client';
const tracer = initTracer(config, options);

// before — zipkin-js (JSON over HTTP to the Zipkin collector)
import { Tracer, ExplicitContext, BatchRecorder } from 'zipkin';
import { HttpLogger } from 'zipkin-transport-http';
const zipkinTracer = new Tracer({
  ctxImpl: new ExplicitContext(),
  recorder: new BatchRecorder({ logger: new HttpLogger({ endpoint }) }),
});
// plus zipkin-instrumentation-express / -fetch middleware on the app

// after — OTel SDK exporting OTLP http/protobuf to the platform proxy:
// the bootstrap above (NodeSDK + OTLPTraceExporter from -otlp-proto), plus
// @opentelemetry/instrumentation-http and the framework instrumentation.
// Remove jaeger-client, zipkin, zipkin-transport-*, zipkin-instrumentation-*
// from the manifest — one active tracing stack only.
```

The exporter reads `OTEL_EXPORTER_OTLP_*` from the environment — keep endpoint and
protocol in config, not hardcoded (see [`config-migration.md`](config-migration.md)).

### Framework instrumentation (`sdk` mechanism)

```ts
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { HttpInstrumentation } from '@opentelemetry/instrumentation-http';
import { ExpressInstrumentation } from '@opentelemetry/instrumentation-express';
import { UndiciInstrumentation } from '@opentelemetry/instrumentation-undici';

registerInstrumentations({
  instrumentations: [
    new HttpInstrumentation(),
    new ExpressInstrumentation(),
    new UndiciInstrumentation(), // global fetch — -http does not cover it
  ],
});
```

**Register each instrumentation once, through one path** — the XOR against the
launcher and the `NodeSDK({ instrumentations })` alternative are Step 0b in
[`../models/4-transformation.md`](../models/4-transformation.md). Per-stack package
sets, including the NestJS adapter and the Fastify plugin:
[`../reference/framework-coverage.md`](../reference/framework-coverage.md).

## Mechanical rewrites (may apply on confirmation)

Deterministic, one-to-one, no control-flow change:

| Before              | After                     |
| ------------------- | ------------------------- |
| `span.finish()`     | `span.end()`              |
| `span.setTag(k, v)` | `span.setAttribute(k, v)` |

`setAttribute` accepts only `string`, `number`, `boolean`, or arrays of those. An
OpenTracing tag holding an object, `null`, or `undefined` is dropped with a
diagnostic warning — flag those call sites instead of rewriting them blindly, and
propose an explicit serialization.

## Structural rewrites (propose, never auto-apply)

These change control flow or replace a whole bootstrap, so they need a human diff:

| Before                                 | After                                                                                         |
| -------------------------------------- | --------------------------------------------------------------------------------------------- |
| `opentracing…startSpan(name)`          | `tracer.startActiveSpan(name, cb)` — body moves into the callback, `end()` moves to `finally` |
| `span.setTag('error', true)`           | `span.recordException(err)` + `span.setStatus({ code: SpanStatusCode.ERROR })`                |
| `initTracer(...)`                      | `NodeSDK` + OTLP proto exporter (whole bootstrap replaced)                                    |
| `new Tracer({...})` + zipkin transport | `NodeSDK` + OTLP proto exporter + OTel instrumentations                                       |
| `opentracing.globalTracer()` use       | `trace.getTracer(name)` + `trace.getActiveSpan()`                                             |

## Guardrails

- Attribute renames toward semantic conventions (custom `http_path` → `http.route`,
  business keys) go to `codeMigration.semantic` — never auto-applied, common
  [`models/4-transformation.md`](../../opentelemetry-tracing-common/models/4-transformation.md)
  §4.3.
- Never write secrets or unbounded payloads to span attributes.
- Prefer `startActiveSpan` (activates the span in context) over `startSpan`
  (creates a detached span you must pass manually) unless you deliberately manage
  context yourself.
- Every hand-written span ends on every path, including the throw path —
  `startActiveSpan` does not end it for you.
