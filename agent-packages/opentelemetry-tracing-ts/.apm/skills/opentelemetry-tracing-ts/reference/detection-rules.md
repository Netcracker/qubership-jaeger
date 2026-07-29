# Detection rules (TypeScript / Node)

Layer 1 signature catalogue for TypeScript/Node services. Detection is **generic
and signature-based** — match imports/symbols/keys, and classify to a first-class
framework only on confident evidence; otherwise `unknown`. Scan `.ts`, `.tsx`,
`.mts`, `.cts`, `.js`, `.mjs`, `.cjs`, plus `package.json`.

## Dependency signatures (package.json / lockfiles)

npm package names as they appear in `package.json` / `package-lock.json` /
`yarn.lock` / `pnpm-lock.yaml`.

| Package | Bucket | Technology |
| ------------------------------------------------------------ | -------- | ---------------------- |
| `opentracing` | legacy | opentracing |
| `jaeger-client` | legacy | jaeger-client |
| `zipkin`, `zipkin-instrumentation-*`, `zipkin-transport-*` | legacy | zipkin |
| `@opentelemetry/exporter-jaeger` (retired) | legacy | jaeger-client |
| `@opentelemetry/exporter-zipkin` | legacy | zipkin |
| `@opentelemetry/api` | modern | otel-api |
| `@opentelemetry/sdk-trace-node`, `@opentelemetry/sdk-trace-base`, `@opentelemetry/sdk-node` | modern | otel-sdk |
| `@opentelemetry/exporter-trace-otlp-proto` | modern | otel-exporter |
| `@opentelemetry/exporter-trace-otlp-http` | modern | otel-exporter |
| `@opentelemetry/exporter-trace-otlp-grpc` | modern | otel-exporter |
| `@opentelemetry/propagator-b3` | modern | otel-propagator |
| `@opentelemetry/instrumentation`, `@opentelemetry/instrumentation-*` | modern | otel-instrumentation |
| `@opentelemetry/auto-instrumentations-node` | modern | otel-auto |

`@opentelemetry/core`, `@opentelemetry/resources`, `@opentelemetry/semantic-conventions`
are OTel support packages — record them as `other`/`modern` context, not as the
exporter/propagator/SDK signal on their own.

Aggregate flags:

- `hasOtelApi`: OTel API package present.
- `hasOtelSdk`: OTel SDK package present (`sdk-trace-node`/`-base`/`sdk-node`).
- `hasExporter`: OTLP/Zipkin/Jaeger exporter package present.
- `hasLegacy`: legacy tracer stack wired (not just transitive).

### OTLP exporter encoding (record on the export object)

- `@opentelemetry/exporter-trace-otlp-proto` → `http/protobuf` (**contract**)
- `@opentelemetry/exporter-trace-otlp-http` → `http/json`
- `@opentelemetry/exporter-trace-otlp-grpc` → gRPC

`OTEL_EXPORTER_OTLP_PROTOCOL` only decides the encoding when the exporter is
auto-selected by `@opentelemetry/sdk-node` from env. A hardcoded
`new OTLPTraceExporter()` from a specific package fixes the encoding regardless.

## Framework signatures

| Framework | Signature |
| ----------- | ------------------------------------------------------------------------------- |
| `express` | `import express` / `require('express')`; `const app = express()`; `app.listen(...)` |
| `fastify` | `import Fastify` / `require('fastify')`; `Fastify()`; `app.listen(...)` |
| `nestjs` | `@nestjs/core`, `NestFactory.create(...)`; `@Module`/`@Controller` decorators |
| `pure-node` | OTel wiring with no web framework import (worker/CLI/consumer/`http.createServer` only) |

Best-effort: Koa (`@opentelemetry/instrumentation-koa`), Hapi
(`-hapi`), Restify (`-restify`), Connect (`-connect`), gRPC (`-grpc`) — when
confidently identified, prefer the matching contrib instrumentation; otherwise
emit `unknown` + note. Mapping: [`framework-coverage.md`](framework-coverage.md).

## Runtime axes (module system + bundling)

| Axis | Signature |
| ------------------ | ------------------------------------------------------------------------------- |
| ESM | `package.json` `"type": "module"`, `.mjs`, `tsconfig` `module: NodeNext/ESNext` + `import`/`export` |
| CommonJS | `"type": "commonjs"` or absent, `.cjs`, `require`/`module.exports`, `tsconfig` `module: CommonJS` |
| Dual | package exports both (`exports` conditionals), or mixed `.mjs`/`.cjs` |
| Bundled | esbuild/webpack/rollup/tsup/`@vercel/ncc`/swc bundle config; a single `dist/index.js` deployed; `bundle: true` |

Module system drives the instrumentation hook (CJS `-r` vs ESM `--import`);
bundling drives whether monkey-patch auto-instrumentation survives.

## Configuration signatures

Platform-level keys (from the common platform contract):

- `TRACING_ENABLED`
- `TRACING_HOST` (default `nc-diagnostic-agent`)
- `TRACING_SAMPLER_RATELIMITING`
- `TRACING_SAMPLER_PROBABILISTIC`
- `TRACING_SAMPLER_CONST`

OTel keys:

- `OTEL_EXPORTER_OTLP_ENDPOINT` (base URL — the exporter appends `/v1/traces`)
- `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` (used as-is — must include `/v1/traces`)
- `OTEL_EXPORTER_OTLP_PROTOCOL` (`http/protobuf` expected; effective only on env-selected exporter)
- `OTEL_PROPAGATORS` (contract default `b3multi`; runtime scope — drives inject
  and extract; an already-configured format is preserved, not replaced)
- `OTEL_TRACES_SAMPLER`
- `OTEL_TRACES_SAMPLER_ARG`
- `OTEL_SERVICE_NAME` / `OTEL_RESOURCE_ATTRIBUTES`
- `OTEL_NODE_RESOURCE_DETECTORS`
- `NODE_OPTIONS` (may carry `--require`/`--import` for the launcher)

Legacy/framework keys:

- `JAEGER_AGENT_HOST`, `JAEGER_AGENT_PORT`, `JAEGER_SAMPLER_PARAM`, `JAEGER_ENDPOINT`
- `ZIPKIN_ENDPOINT` / hardcoded Zipkin URL

## Code signatures

OTel:

- `trace.getTracer(...)` / `trace.setGlobalTracerProvider(...)`
- `tracer.startActiveSpan(...)` / `tracer.startSpan(...)`
- `trace.getActiveSpan(...)`
- `new NodeSDK({...})` / `new NodeTracerProvider({...})` + `.register()`
- `registerInstrumentations({...})` / `getNodeAutoInstrumentations(...)`
- `propagation.setGlobalPropagator(...)` / `new CompositePropagator({...})`
- `new B3Propagator()` (defaults to single `b3`) vs
  `new B3Propagator({ injectEncoding: B3InjectEncoding.MULTI_HEADER })` (`X-B3-*`)
- `OTLPTraceExporter` from `@opentelemetry/exporter-trace-otlp-proto` (http/protobuf)
- `ExpressInstrumentation` / `FastifyInstrumentation` / `NestInstrumentation` / `HttpInstrumentation`

Legacy:

- `opentracing` global tracer / `initGlobalTracer`
- `jaeger-client` `initTracer` / `new Tracer`
- `zipkin` `Tracer` / `zipkin-instrumentation-*`

## Instrumentation mode signatures

| Evidence | Mode |
| ------------------------------------------------------------- | -------- |
| `auto-instrumentations-node/register` via `-r`/`--require`/`NODE_OPTIONS`/`--import`, no app spans | auto |
| `registerInstrumentations({...})` / `getNodeAutoInstrumentations()`, no app spans | auto |
| Explicit `startActiveSpan`/`startSpan` in app code | manual |
| Both auto path and explicit spans | mixed |
| No symbols from table | none |

`mode` is the coarse **detected** state. For the **target** mechanism the
transformation gate distinguishes `launcher` (the register/`-r` launcher) from
`sdk` (programmatic `NodeSDK` + `registerInstrumentations`) — both surface here as
`auto`. See [`../models/4-transformation.md`](../models/4-transformation.md) Step 0b.

## Async-boundary signatures

| Symbol/pattern | Boundary type |
| ------------------------------------------------------------- | --------------------------------- |
| `worker_threads`, `new Worker(...)`, Piscina | worker-thread |
| `child_process` `spawn`/`fork`/`exec` | child-process |
| `kafkajs` / `node-rdkafka` produce/consume | kafka-producer / kafka-consumer |
| `amqplib`, `bull`/`bullmq`, SQS (`@aws-sdk`), `nats` | message-queue |
| `EventEmitter` listener detached from the emitting scope | event-emitter |
| outbound HTTP client in a worker/consumer | http-client |

Plain `async`/`await`, resolved Promises, `setTimeout`/`setImmediate`, and
`queueMicrotask` propagate context via `AsyncLocalStorage` — **not** a loss
candidate, do not record them. Mark a boundary as a context-loss candidate when no
explicit context propagation is visible (`context.with`/`context.bind`, OTel
Kafka/messaging instrumentation, or manual inject/extract). A provider built from
`BasicTracerProvider` without the Node context manager loses context even across
`await` — record it as a setup gap.

## Platform-contract signatures

Map to mandatory checks:

- `service.name=${name}-${namespace}` or equivalent runtime construction;
- namespace source via Downward API, Helm `.Release.Namespace`, or serviceaccount file;
- OTLP endpoint `http://${TRACING_HOST}:4318/v1/traces` (or equivalent host+path composition);
- exporter package `@opentelemetry/exporter-trace-otlp-proto` (http/protobuf);
- propagation `b3multi` (or explicitly documented compatible format);
- sampler uses parent-based ratio behavior in production (`parentbased_traceidratio`);
- probe/metrics endpoint exclusions (`/health*`, `/metrics`, `/prometheus`, `/livez`, `/readyz`);
- log format includes `traceId` and `spanId`.
