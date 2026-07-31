# Layer 1 — Discovery (TypeScript / Node)

**Goal:** enumerate every existing element of tracing implementation.
Discovery reports what exists, not whether it works.

- **Input:** repository root (TypeScript/JavaScript source, `package.json` and
  lockfiles, `tsconfig.json`, bundler config, config, deployment, Helm/k8s).
- **Output:** `discovery-result.json` validated by
  [`../schemas/L1-discovery-result.schema.json`](../schemas/L1-discovery-result.schema.json).
- **Detection signatures:** [`../reference/detection-rules.md`](../reference/detection-rules.md).

Run sections **1.0–1.6**; emit every required JSON object. Missing evidence →
`unknown` or empty arrays per schema; record why in `gaps` — do not omit sections.

## 1.0 Framework and runtime discovery

Set `service.framework` (schema enum) and optional `service.name`. Detect from
**generic signatures** (imported web framework, HTTP server bootstrap), not from
a fixed whitelist — classify to a first-class value only when the evidence is
confident, otherwise `unknown`. First-class coverage and best-effort fallbacks:
[`../reference/framework-coverage.md`](../reference/framework-coverage.md).

| Framework   | Typical evidence                                                                            |
| ----------- | ------------------------------------------------------------------------------------------- |
| `express`   | `import express` / `require('express')`; `express()` app; `app.listen(...)`                 |
| `fastify`   | `import Fastify` / `require('fastify')`; `fastify()` instance; `app.listen(...)`            |
| `nestjs`    | `@nestjs/core`, `NestFactory.create(...)`, `@Module`/`@Controller` decorators               |
| `pure-node` | OTel wired without a web framework above (worker, CLI, library, consumer, http.Server only) |
| `unknown`   | insufficient or best-effort evidence (Koa, Hapi, Restify, GraphQL, Next.js…) — see below    |

The enum has no value for the best-effort frameworks. When one is identified
confidently, keep `service.framework` at `unknown` **and** record it in `gaps` as
`framework: <name> (best-effort)` — that exact phrasing is what the Step 0 `unknown`
row reads to route to the matching contrib instrumentation instead of the bare SDK.

Also resolve two runtime axes that drive the whole migration in Node:

- **`service.moduleSystem`** — `esm` / `commonjs` / `dual` / `unknown`. Read
  `package.json` `"type"`, `tsconfig.json` `compilerOptions.module` /
  `moduleResolution`, and `.mjs`/`.cjs` extensions. This decides the
  instrumentation hook (CommonJS `-r`/`--require` vs ESM `--import` + loader hook)
  — see [`../models/4-transformation.md`](../models/4-transformation.md) Step 0b.
- **`service.bundled`** — true when the deployed artifact is produced by a bundler
  (esbuild/webpack/rollup/tsup/swc bundle, `ncc`, a single `dist/index.js`).
  Bundling inlines `require`/`import` and can defeat monkey-patch
  auto-instrumentation; record it here so L4 picks a mechanism that survives it
  ([`../reference/build-preconditions.md`](../reference/build-preconditions.md)).

## 1.1 Dependency discovery

Inputs:

- `package.json` (`dependencies`, `devDependencies`, `peerDependencies`,
  `optionalDependencies`); workspace roots (npm/yarn/pnpm workspaces, lerna, nx, turbo);
- lockfiles: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `npm-shrinkwrap.json`;
- optional `npm ls` / `pnpm why` output for transitive resolution.

Classify tracing artifacts into buckets (catalogue in `detection-rules.md`):

- **legacy**: `opentracing`, `jaeger-client`, `zipkin` /
  `zipkin-instrumentation-*`, the retired `@opentelemetry/exporter-jaeger`,
  and non-OTel APM agents used as the tracing stack (`dd-trace`,
  `elastic-apm-node`, `newrelic`) when they **are** the tracing stack. Map
  `@opentelemetry/exporter-jaeger` and `@opentelemetry/exporter-zipkin` to
  `bucket: legacy`, `technology: otel-exporter` — they are retired or off-contract
  OTel exporters, not the `jaeger-client`/`zipkin` tracers;
- **modern**: `@opentelemetry/api`, `@opentelemetry/sdk-trace-node` /
  `@opentelemetry/sdk-trace-base` / `@opentelemetry/sdk-node`, OTLP exporters
  (`@opentelemetry/exporter-trace-otlp-proto` / `-otlp-http` / `-otlp-grpc`), the
  B3 propagator (`@opentelemetry/propagator-b3`), instrumentation packages
  (`@opentelemetry/instrumentation-*`), and the auto-instrumentation meta package
  (`@opentelemetry/auto-instrumentations-node`).

Set aggregate flags:

- `hasOtelApi`
- `hasOtelSdk`
- `hasExporter`
- `hasLegacy`

## 1.2 Configuration discovery

Inspect config/env locations:

- `.env`, Helm values/templates, Deployment env vars;
- app config (`process.env` reads, `dotenv`, `config`/`convict` modules, NestJS
  `ConfigModule`);
- the tracing bootstrap file (`tracing.ts`/`instrumentation.ts`/`otel.ts` or a
  `NodeSDK`/`NodeTracerProvider` setup) and any programmatic SDK wiring in
  `.ts`/`.js`;
- the **runtime launch surface** — `package.json` `scripts` (`start`, `start:prod`),
  Dockerfile `CMD`/`ENTRYPOINT`, Helm `command`/`args`, and `NODE_OPTIONS`. This is
  the only place the instrumentation hook is visible.

Collect:

- export endpoint/protocol/target guess (**and the exporter package** — the
  package name, not just the env var, determines the OTLP encoding: see below);
- propagation **inject** and **extract** sets (separately — see below) and per-component wiring (HTTP/Kafka/async);
- sampler type and ratio;
- `service.entrypoint` — the resolved launch command, verbatim;
- `instrumentation.hook` — how the bootstrap is loaded: `require` (`-r`/`--require`
  or `NODE_OPTIONS`), `import` (ESM `--import`), `loader+import`
  (`--experimental-loader=@opentelemetry/instrumentation/hook.mjs` **plus**
  `--import`), `none`, or `unknown`. Record what the command **actually** contains;
  do not infer it from `moduleSystem`. The mismatch is the finding: ESM plus a
  launcher with `import` alone and no loader hook means monkey-patch
  instrumentation never wraps anything, and the service exports an empty trace
  while every dependency and env var looks correct.

### Export encoding is set by the package, not only the env var

In Node the OTLP encoding follows the **exporter package**:
`@opentelemetry/exporter-trace-otlp-proto` = `http/protobuf` (contract),
`@opentelemetry/exporter-trace-otlp-http` = `http/json`,
`@opentelemetry/exporter-trace-otlp-grpc` = gRPC. `OTEL_EXPORTER_OTLP_PROTOCOL`
only takes effect when the exporter is auto-selected from the environment
(`@opentelemetry/sdk-node` with no explicit exporter). When code does
`new OTLPTraceExporter()` imported from a specific package, that package fixes the
encoding regardless of the env var. Record the resolved `protocol` from whichever
wins.

### Propagation: two sets, resolved from the actual configuration

Record `propagation.inject` and `propagation.extract` separately. On **extract** a
`CompositePropagator` chains the context through each member in order (implemented
as a `reduce`), so the **last** member that finds a context wins — same as the Go
and OTel-native composites in the common guide. On **inject** it fans out —
writing **all** configured formats, each to its own carrier keys. A merged list
hides the case where a service reads B3 and still emits only `traceparent`. Record
the order as written; do not reorder or dedupe it. See
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Propagation.

Sources, both `runtime` scope in Node (there is no build-time propagation
surface):

- `OTEL_PROPAGATORS` env (`b3`, `b3multi`, `tracecontext`, `jaeger`, …);
- programmatic `propagation.setGlobalPropagator(...)` — read the **class and its
  options**, not just the presence of B3. `new B3Propagator()` **defaults to
  `B3InjectEncoding.SINGLE_HEADER`** — it injects the **single** `b3` header;
  `b3multi` (`X-B3-TraceId`/`X-B3-SpanId`/`X-B3-Sampled`) requires
  `new B3Propagator({ injectEncoding: B3InjectEncoding.MULTI_HEADER })`. The env
  value `b3` maps to single-header, `b3multi` to multi-header. Mechanism and
  source coordinates:
  [`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
  §Verify constructor defaults — check them against the `@opentelemetry/propagator-b3`
  version in the repo's `package.json`, not the version cited there.

If **both** `OTEL_PROPAGATORS` and a programmatic `setGlobalPropagator(...)` are
present, **the first registration wins**. `@opentelemetry/api` refuses a duplicate
global registration: the losing call returns `false` and logs
`Attempted duplicate registration of API: propagation` through `diag`.
`provider.register()` / `sdk.start()` registers the env-derived propagator, so:

- `setGlobalPropagator(...)` **before** `register()`/`start()` — the programmatic
  propagator is effective and `OTEL_PROPAGATORS` is ignored;
- `setGlobalPropagator(...)` **after** it (the usual bootstrap layout) — the call is
  **rejected** and the env value stays effective.

Resolve the winner by **call order in the bootstrap file**, not by kind, and record
the loser in `gaps`: a rejected call is dead code that reads like configuration.
The same first-wins rule applies to `trace.setGlobalTracerProvider`.

If no propagator is configured at all, the SDK default is **W3C tracecontext +
baggage** — record `inject`/`extract` as `["w3c"]` with `fromFrameworkDefault: true`,
not `none`.

## 1.3 API discovery (AST/symbol)

Find symbols across `.ts`/`.tsx`/`.js`/`.mjs`/`.cjs`:

- OTel: `trace.getTracer`, `tracer.startActiveSpan`, `tracer.startSpan`,
  `trace.getActiveSpan`, `NodeTracerProvider`, `NodeSDK`, `trace.setGlobalTracerProvider`,
  `propagation.setGlobalPropagator`, `registerInstrumentations`;
- legacy: `opentracing` global tracer, `jaeger-client` `initTracer`/`new Tracer`,
  `zipkin` (`Tracer`, `zipkin-instrumentation-*`) symbols;
- framework instrumentations (`ExpressInstrumentation`, `NestInstrumentation`,
  `HttpInstrumentation`, `UndiciInstrumentation`, `FastifyOtelInstrumentation`) —
  signatures in `detection-rules.md`. `FastifyInstrumentation` from
  `@opentelemetry/instrumentation-fastify` is a **deprecated** stack: record it and
  raise the replacement (`@fastify/otel`) as a gap.

Record `family`, `symbol`, `file`, `line`.

## 1.4 Instrumentation discovery

Classify `instrumentation.mode`:

- `auto`: no explicit spans but zero-code launcher evidence
  (`@opentelemetry/auto-instrumentations-node/register` via `-r`/`--require` or
  `NODE_OPTIONS`, ESM `--import`) or programmatic `registerInstrumentations({...})`
  / `getNodeAutoInstrumentations()` calls;
- `manual`: explicit span creation in app code (`startActiveSpan`/`startSpan`);
- `mixed`: both;
- `none`: no evidence.

Then classify `instrumentation.mechanism` — `mode` is shared across languages and
collapses two different Node setups into `auto`, while
[`../models/4-transformation.md`](4-transformation.md) Step 0b plans against three:

| Evidence                                                                     | `mechanism`  |
| ---------------------------------------------------------------------------- | ------------ |
| `auto-instrumentations-node/register` loaded via `-r`/`--require`/`--import` | `launcher`   |
| `NodeSDK` / `NodeTracerProvider` + `registerInstrumentations({...})` in code | `sdk`        |
| Only hand-written `startActiveSpan`/`startSpan`, no instrumentation packages | `hand-spans` |
| No tracing setup at all                                                      | `none`       |
| Evidence conflicts or is unreadable                                          | `unknown`    |

Launcher **and** programmatic `registerInstrumentations` for the same library is a
finding, not a `mechanism` value — record `unknown` plus a `gap`, and let Step 0b
resolve the XOR.

## 1.5 Async-boundary discovery

Detect context-loss candidates. **Note:** with the Node context manager
(`AsyncLocalStorageContextManager`, registered automatically by
`NodeTracerProvider.register()` / `NodeSDK`), OTel context propagates
automatically across `await`, resolved Promises, `queueMicrotask`, `setTimeout`,
`setImmediate`, and most callback APIs — so plain `async`/`await` is **not** a
loss boundary; do not record it as one. The real losses are:

- worker threads (`worker_threads`, `new Worker(...)`, Piscina) — separate thread,
  `AsyncLocalStorage` does not cross it;
- child processes / subprocess (`child_process` `spawn`/`fork`/`exec`);
- Kafka producers/consumers (`kafkajs`, `node-rdkafka`) and other messaging libs;
- message queues / background jobs (`amqplib` / RabbitMQ, `bull`/`bullmq`,
  `@aws-sdk` SQS, `nats`);
- `EventEmitter` listeners that run detached from the originating async context
  (emitted after the store scope exited);
- outbound HTTP clients in a worker/consumer when made outside an active span.

Mark `contextWrapper` true only when context is explicitly propagated (captured
`context.with(...)` / `context.bind(...)`, OTel Kafka/messaging instrumentation,
or manual inject/extract).

**Setup pitfall (record as a boundary/gap when present):** a provider built from
`@opentelemetry/sdk-trace-base` `BasicTracerProvider` without the Node context
manager loses context even across a plain `await`. Prefer
`@opentelemetry/sdk-trace-node` `NodeTracerProvider` or `NodeSDK`, which register
the `AsyncLocalStorageContextManager`.

## 1.6 Platform-contract discovery

Collect mandatory contract evidence:

- `TRACING_ENABLED`, `TRACING_HOST`, `TRACING_SAMPLER_*`;
- **sampler tier** (`samplerTier`) — which of `TRACING_SAMPLER_RATELIMITING` /
  `TRACING_SAMPLER_PROBABILISTIC` / `TRACING_SAMPLER_CONST` is wired, per the
  contract priority ratelimiting > probabilistic > const. The Node OTel SDK has
  **no native rate-limiting sampler**, so a wired `TRACING_SAMPLER_RATELIMITING`
  cannot be honored natively — record it in `gaps` and expect a parent-based ratio
  approximation at L4 (this is distinct from `samplerType`, the OTel sampler class);
- OTLP `http/protobuf` path and host alias (and the exporter package that fixes
  the encoding);
- propagation — the injected format (contract default `b3multi`) and the
  extracted set, resolved from the propagator class/options/env value;
- `parentbased_traceidratio` or equivalent parent-based ratio behavior;
- `service.name=${name}-${namespace}` and namespace source
  (Downward API/Helm/SA file);
- excluded probe/metrics endpoints;
- `traceId`/`spanId` in log output.

For missing inspectable evidence, use `unknown` and record `gaps`.

## Output example

One JSON object validated against
[`../schemas/L1-discovery-result.schema.json`](../schemas/L1-discovery-result.schema.json):

```json
{
  "service": {
    "name": "order-service", "framework": "express", "moduleSystem": "commonjs", "bundled": false,
    "entrypoint": "node -r ./dist/tracing.js dist/main.js"
  },
  "dependencyProfile": {
    "hasOtelApi": true, "hasOtelSdk": true, "hasExporter": true, "hasLegacy": false,
    "artifacts": [
      { "coordinates": "@opentelemetry/api", "version": "1.x", "scope": "dependencies", "bucket": "modern", "technology": "otel-api" },
      { "coordinates": "@opentelemetry/sdk-node", "version": "0.5x", "scope": "dependencies", "bucket": "modern", "technology": "otel-sdk" },
      { "coordinates": "@opentelemetry/exporter-trace-otlp-http", "version": "0.5x", "scope": "dependencies", "bucket": "modern", "technology": "otel-exporter" },
      { "coordinates": "@opentelemetry/propagator-b3", "version": "1.x", "scope": "dependencies", "bucket": "modern", "technology": "otel-propagator" }
    ]
  },
  "configuration": {
    "export": { "exporter": "otlp", "endpoint": "http://nc-diagnostic-agent:4318/v1/traces", "protocol": "http/json", "targetGuess": "otec" },
    "propagation": {
      "inject": ["b3"], "extract": ["b3", "w3c"],
      "configScope": "runtime", "fromFrameworkDefault": false,
      "components": { "http": "OK", "kafka": "FAILED" }
    },
    "sampling": { "configured": true, "type": "parentbased", "ratio": 0.01, "consistentAcrossServices": "unknown" }
  },
  "apiUsage": [
    { "family": "otel", "symbol": "new B3Propagator", "file": "src/tracing.ts", "line": 12 }
  ],
  "apiFamilies": ["otel"],
  "instrumentation": {
    "mode": "auto", "mechanism": "sdk", "hook": "require",
    "evidence": ["registerInstrumentations in src/tracing.ts", "no hand-written spans", "package.json scripts.start: node -r ./dist/tracing.js"]
  },
  "asyncBoundaries": [
    { "type": "worker-thread", "file": "src/jobs/report.worker.ts", "line": 8, "contextWrapper": false }
  ],
  "platformContract": {
    "serviceName": { "value": "order-service", "includesNamespace": false, "namespaceSource": "none" },
    "samplerTier": "probabilistic",
    "samplerType": "parentbased_traceidratio",
    "propagationStandard": "b3",
    "hasB3PropagatorExtension": true,
    "endpointFilter": { "configured": false, "excluded": [] },
    "logging": { "traceFieldsInPattern": false, "correlationDep": "none" },
    "export": { "protocol": "http/json", "endpointPath": "/v1/traces", "tracingHost": "nc-diagnostic-agent" }
  },
  "gaps": [
    "exporter is exporter-trace-otlp-http (JSON) — contract wants http/protobuf via exporter-trace-otlp-proto",
    "B3Propagator constructed with no options — injects single b3, contract default is b3multi"
  ]
}
```

The two `gaps` above are the classic Node contract misses — a JSON exporter where
the contract wants protobuf, and a single-`b3` propagator where it wants `b3multi`
— both of which pass every end-to-end test while being wrong on the wire.

## User-facing brief (mandatory)

After `discovery-result.json`, post the **L1 Discovery brief** in chat per
[`../SKILL.md`](../SKILL.md) §3.1 (5–10 bullets: framework, module system +
bundling, dependencies, config, instrumentation, async boundaries, platform gaps).
Do not proceed to L2 until posted.
