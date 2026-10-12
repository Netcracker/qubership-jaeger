# Detection rules (TypeScript / Node)

Layer 1 signature catalogue for TypeScript/Node services. Detection is **generic
and signature-based** — match imports/symbols/keys, and classify to a first-class
framework only on confident evidence; otherwise `unknown`. Scan `.ts`, `.tsx`,
`.mts`, `.cts`, `.js`, `.mjs`, `.cjs`, plus `package.json`.

## Dependency signatures (package.json / lockfiles)

npm package names as they appear in `package.json` / `package-lock.json` /
`yarn.lock` / `pnpm-lock.yaml`.

| Package                                                                                     | Bucket | Technology           |
| ------------------------------------------------------------------------------------------- | ------ | -------------------- |
| `opentracing`                                                                               | legacy | opentracing          |
| `jaeger-client`                                                                             | legacy | jaeger-client        |
| `zipkin`, `zipkin-instrumentation-*`, `zipkin-transport-*`                                  | legacy | zipkin               |
| `@opentelemetry/exporter-jaeger` (retired)                                                  | legacy | otel-exporter        |
| `@opentelemetry/exporter-zipkin`                                                            | legacy | otel-exporter        |
| `dd-trace`, `elastic-apm-node`, `newrelic`                                                  | legacy | other                |
| `@opentelemetry/api`                                                                        | modern | otel-api             |
| `@opentelemetry/sdk-trace-node`, `@opentelemetry/sdk-trace-base`, `@opentelemetry/sdk-node` | modern | otel-sdk             |
| `@opentelemetry/exporter-trace-otlp-proto`                                                  | modern | otel-exporter        |
| `@opentelemetry/exporter-trace-otlp-http`                                                   | modern | otel-exporter        |
| `@opentelemetry/exporter-trace-otlp-grpc`                                                   | modern | otel-exporter        |
| `@opentelemetry/propagator-b3`                                                              | modern | otel-propagator      |
| `@opentelemetry/instrumentation`, `@opentelemetry/instrumentation-*`                        | modern | otel-instrumentation |
| `@opentelemetry/auto-instrumentations-node`                                                 | modern | otel-auto            |

`@opentelemetry/core`, `@opentelemetry/resources`, `@opentelemetry/semantic-conventions`
are OTel support packages — record them as `other`/`modern` context, not as the
exporter/propagator/SDK signal on their own. `@opentelemetry/instrumentation` (the
base library) is supporting evidence too: every `-instrumentation-*` package and the
ESM loader hook pull it in transitively, so on its own it does not prove anything is
instrumented.

The retired `@opentelemetry/exporter-jaeger` and the off-contract
`@opentelemetry/exporter-zipkin` are **OTel exporters in the legacy bucket**, not
legacy tracers: the `jaeger-client` and `zipkin` technology values stay reserved for
the client libraries themselves, so L4 does not confuse "replace the exporter" with
"remove the tracer".

A non-OTel APM agent counts as `legacy` **only when it is the tracing stack**. An
agent installed for metrics or profiling alongside OTel tracing is not a legacy
tracer — record it in `gaps` instead, and note the double-instrumentation risk.

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

| Framework   | Signature                                                                               |
| ----------- | --------------------------------------------------------------------------------------- |
| `express`   | `import express` / `require('express')`; `const app = express()`; `app.listen(...)`     |
| `fastify`   | `import Fastify` / `require('fastify')`; `Fastify()`; `app.listen(...)`                 |
| `nestjs`    | `@nestjs/core`, `NestFactory.create(...)`; `@Module`/`@Controller` decorators           |
| `pure-node` | OTel wiring with no web framework import (worker/CLI/consumer/`http.createServer` only) |

Best-effort stacks (Koa, Hapi, Restify, Connect, gRPC, GraphQL/Apollo, Socket.IO,
Next.js, Hono/Elysia) have no enum value: detect them generically, keep
`service.framework` at `unknown`, and take the instrumentation mapping and the
`gaps` phrasing from [`framework-coverage.md`](framework-coverage.md).

## Runtime axes (module system + bundling)

| Axis     | Signature                                                                                                      |
| -------- | -------------------------------------------------------------------------------------------------------------- |
| ESM      | `package.json` `"type": "module"`, `.mjs`, `tsconfig` `module: NodeNext/ESNext` + `import`/`export`            |
| CommonJS | `"type": "commonjs"` or absent, `.cjs`, `require`/`module.exports`, `tsconfig` `module: CommonJS`              |
| Dual     | package exports both (`exports` conditionals), or mixed `.mjs`/`.cjs`                                          |
| Bundled  | esbuild/webpack/rollup/tsup/`@vercel/ncc`/swc bundle config; a single `dist/index.js` deployed; `bundle: true` |

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
- `ExpressInstrumentation` / `NestInstrumentation` / `HttpInstrumentation` /
  `UndiciInstrumentation`
- `FastifyOtelInstrumentation` from `@fastify/otel`, registered via
  `app.register(instr.plugin())` or `registerOnInitialization: true` (current Fastify path)
- `FastifyInstrumentation` from `@opentelemetry/instrumentation-fastify` — the
  **deprecated** Fastify path; record it and raise `@fastify/otel` as a gap
- absence of `UndiciInstrumentation` in a service that calls `fetch()` — no client
  span and no trace headers on those calls; record as a gap

Legacy:

- `opentracing` global tracer / `initGlobalTracer`
- `jaeger-client` `initTracer` / `new Tracer`
- `zipkin` `Tracer` / `zipkin-instrumentation-*`

## Instrumentation mode signatures

| Evidence                                                                                           | Mode   |
| -------------------------------------------------------------------------------------------------- | ------ |
| `auto-instrumentations-node/register` via `-r`/`--require`/`NODE_OPTIONS`/`--import`, no app spans | auto   |
| `registerInstrumentations({...})` / `getNodeAutoInstrumentations()`, no app spans                  | auto   |
| Explicit `startActiveSpan`/`startSpan` in app code                                                 | manual |
| Both auto path and explicit spans                                                                  | mixed  |
| No symbols from table                                                                              | none   |

`mode` is the coarse **detected** state, shared with the other language packages.
`instrumentation.mechanism` is the Node-specific one: `launcher` (the register/`-r`
launcher) and `sdk` (programmatic `NodeSDK` + `registerInstrumentations`) both
surface as `mode: auto`. Classification table:
[`../models/1-discovery.md`](../models/1-discovery.md) §1.4; the target mechanism is
planned in [`../models/4-transformation.md`](../models/4-transformation.md) Step 0b.

### Bootstrap load hook (`instrumentation.hook`)

Read from the resolved launch command — Helm `command`/`args`, Dockerfile
`CMD`/`ENTRYPOINT`, `NODE_OPTIONS`, or `package.json` `scripts.start`:

| Evidence                                                                                                   | `hook`          |
| ---------------------------------------------------------------------------------------------------------- | --------------- |
| `-r` / `--require ./tracing.js` (CommonJS), directly or via `NODE_OPTIONS`                                 | `require`       |
| `--import ./tracing.mjs` with no loader flag and no `register()` in the bootstrap                          | `import`        |
| `--experimental-loader=@opentelemetry/instrumentation/hook.mjs` **plus** `--import`                        | `loader+import` |
| `register('@opentelemetry/instrumentation/hook.mjs', import.meta.url)` from `node:module` in the bootstrap | `loader+import` |
| Bootstrap imported from application code only (`import './tracing.js'` at the top of `main.ts`)            | `none`          |
| Launch command not readable                                                                                | `unknown`       |

`hook: import` together with `mechanism: launcher` on an ESM service is the silent
killer: the SDK starts first, but monkey-patch instrumentation never wraps anything
because ESM `import` does not go through `require`. Record it as a `gap`, not as a
working setup.

## Async-boundary signatures

| Symbol/pattern                                           | Boundary type                   |
| -------------------------------------------------------- | ------------------------------- |
| `worker_threads`, `new Worker(...)`, Piscina             | worker-thread                   |
| `child_process` `spawn`/`fork`/`exec`                    | child-process                   |
| `kafkajs` / `node-rdkafka` produce/consume               | kafka-producer / kafka-consumer |
| `amqplib`, `bull`/`bullmq`, SQS (`@aws-sdk`), `nats`     | message-queue                   |
| `EventEmitter` listener detached from the emitting scope | event-emitter                   |
| outbound HTTP client in a worker/consumer                | http-client                     |

Plain `async`/`await`, resolved Promises, `setTimeout`/`setImmediate`, and
`queueMicrotask` propagate context via `AsyncLocalStorage` — **not** a loss
candidate, do not record them. Mark a boundary as a context-loss candidate when no
explicit context propagation is visible (`context.with`/`context.bind`, OTel
Kafka/messaging instrumentation, or manual inject/extract). A provider built from
`BasicTracerProvider` without the Node context manager loses context even across
`await` — record it as a setup gap.

## Sampler signatures

Env keys alone are not enough — a programmatic sampler overrides them, and the
platform contract fails validation when sampling stays `unknown`.

| Evidence                                                                       | `samplerType`                                      |
| ------------------------------------------------------------------------------ | -------------------------------------------------- |
| `new ParentBasedSampler({ root: new TraceIdRatioBasedSampler(r) })`            | `parentbased_traceidratio`                         |
| `new ParentBasedSampler({ root: new AlwaysOnSampler() })` / `AlwaysOffSampler` | `parentbased_always_on` / `parentbased_always_off` |
| `new TraceIdRatioBasedSampler(r)` passed directly as `sampler`                 | `traceidratio`                                     |
| `new AlwaysOnSampler()` / `new AlwaysOffSampler()`                             | `always_on` / `always_off`                         |
| `OTEL_TRACES_SAMPLER` env value                                                | that value verbatim                                |
| No `sampler` option and no `OTEL_TRACES_SAMPLER`                               | `parentbased_always_on` (SDK default)              |

The `sampler` option lives in `new NodeSDK({ sampler })` or
`new NodeTracerProvider({ sampler })`. Record the ratio from the
`TraceIdRatioBasedSampler` argument or `OTEL_TRACES_SAMPLER_ARG`. The platform
sampler tier is resolved separately —
[`../models/1-discovery.md`](../models/1-discovery.md) §1.6.

## Log-correlation signatures

Fills `platformContract.logging`:

| Evidence                                                                                            | `correlationDep`               |
| --------------------------------------------------------------------------------------------------- | ------------------------------ |
| `@opentelemetry/instrumentation-pino` registered                                                    | `otel-pino-instrumentation`    |
| `@opentelemetry/instrumentation-winston` registered                                                 | `otel-winston-instrumentation` |
| `@opentelemetry/instrumentation-bunyan` registered                                                  | `otel-bunyan-instrumentation`  |
| `trace.getActiveSpan()?.spanContext()` inside a logger formatter, pino `mixin`, or a winston format | `custom`                       |
| Logger configured with no trace fields                                                              | `none`                         |

Set `traceFieldsInPattern` from the **emitted field names**, not from the presence
of a dependency: the OTel logging instrumentations inject `trace_id`, `span_id`,
`trace_flags`, while the contract asks for `traceId` and `spanId`. A service can
have correlation wired and still miss the contract shape — that is a finding, not a
pass.

## Endpoint-filter signatures

Fills `platformContract.endpointFilter`:

- `HttpInstrumentation` option `ignoreIncomingRequestHook` (current API) or
  `ignoreIncomingPaths` (older releases) — read the paths it rejects;
- a custom `Sampler` that returns `NOT_RECORD` for probe routes;
- framework-level exclusion (an Express/Fastify route registered outside the
  instrumented app, or a probe served by a separate server instance).

No signature present means `configured: false` with an empty `excluded` — do not
infer filtering from the absence of probe spans.

## Platform-contract signatures

The facets and their required values are common
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md) §Mandatory
contract — read them there, never from a copy in this file. Resolve each one from the Node signals above into
`discovery-result.platformContract`. An absent mandatory signal resolves to `FAILED`, not `UNKNOWN`: common
[`models/2-capability.md`](../../opentelemetry-tracing-common/models/2-capability.md) §Algorithm.

Two Node deltas on the contract:

- `exportShape` reads the **package**, not just the endpoint: `@opentelemetry/exporter-trace-otlp-proto` satisfies the
  contract `http/protobuf`, while `-otlp-http` sends JSON and does not;
- endpoint filtering is per framework, and the Java paths in the contract (`/actuator/*`, `/q/*`) do not apply — the
  signals are the ones under §Endpoint-filter signatures above.
