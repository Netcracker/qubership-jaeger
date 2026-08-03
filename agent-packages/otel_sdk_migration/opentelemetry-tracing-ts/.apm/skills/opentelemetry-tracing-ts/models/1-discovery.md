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

Set `service.framework` (schema enum) and optional `service.name` from
[`../reference/detection-rules.md`](../reference/detection-rules.md) §Framework
signatures. Classify to a first-class value only on confident evidence, otherwise
`unknown` — best-effort handling and the `gaps` phrasing Step 0 reads:
[`../reference/framework-coverage.md`](../reference/framework-coverage.md).

Also resolve the two runtime axes that drive the whole migration in Node
(signatures: `detection-rules.md` §Runtime axes):

- **`service.moduleSystem`** — `esm` / `commonjs` / `dual` / `unknown`. Decides the
  instrumentation hook (CommonJS `-r`/`--require` vs ESM `--import` + loader hook),
  planned in [`../models/4-transformation.md`](../models/4-transformation.md) Step 0b.
- **`service.bundled`** — bundling inlines `require`/`import` and can defeat
  monkey-patch auto-instrumentation; record it here so L4 picks a mechanism that
  survives it
  ([`../reference/build-preconditions.md`](../reference/build-preconditions.md)).

## 1.1 Dependency discovery

Inputs:

- `package.json` (`dependencies`, `devDependencies`, `peerDependencies`,
  `optionalDependencies`); workspace roots (npm/yarn/pnpm workspaces, lerna, nx, turbo);
- lockfiles: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `npm-shrinkwrap.json`;
- optional `npm ls` / `pnpm why` output for transitive resolution.

Classify every tracing artifact into a bucket and set the aggregate flags
(`hasOtelApi`, `hasOtelSdk`, `hasExporter`, `hasLegacy`) — package catalogue,
bucket assignments, and the support-package exclusions:
[`../reference/detection-rules.md`](../reference/detection-rules.md) §Dependency
signatures.

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
- `instrumentation.hook` — record what the launch command **actually** contains
  (§1.4); never infer it from `moduleSystem`. The mismatch between the two is the
  finding, not an inconsistency to smooth over.

Record the resolved export `protocol` from whichever source wins — in Node the
exporter **package** fixes the encoding and the env var only applies to an
env-selected exporter (`detection-rules.md` §OTLP exporter encoding).

### Propagation: two sets, resolved from the actual configuration

Record `propagation.inject` and `propagation.extract` separately, in the order
written — do not reorder or dedupe. Why the two directions differ, and which end of
a composite wins on extract:
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Propagation. Both sources are `runtime` scope in Node; there is no build-time
propagation surface.

Read the propagator **class and its options**, not just the presence of B3 — the
constructor default is single-header `b3`, not `b3multi`
(`detection-rules.md` §Code signatures). Verify it against the
`@opentelemetry/propagator-b3` version in the repo's `package.json`, not against a
version cited elsewhere: guide §Verify constructor defaults.

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

Scan `.ts`/`.tsx`/`.js`/`.mjs`/`.cjs` for the OTel, legacy, and framework-
instrumentation symbols catalogued in
[`../reference/detection-rules.md`](../reference/detection-rules.md) §Code
signatures. Record `family`, `symbol`, `file`, `line` for each hit.

## 1.4 Instrumentation discovery

Classify `instrumentation.mode` (`auto` / `manual` / `mixed` / `none`) from
`detection-rules.md` §Instrumentation mode signatures, and `instrumentation.hook`
from §Bootstrap load hook.

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

Record each context-loss candidate with its boundary type and `contextWrapper`
flag. Boundary catalogue, the `AsyncLocalStorage` exemptions (plain `async`/`await`
is **not** a loss boundary), and the `BasicTracerProvider` setup gap:
[`../reference/detection-rules.md`](../reference/detection-rules.md)
§Async-boundary signatures.

## 1.6 Platform-contract discovery

Resolve every facet of `platformContract` from the Node signals — signature
sources and the two Node deltas:
[`../reference/detection-rules.md`](../reference/detection-rules.md)
§Platform-contract signatures.

One field is L1's own decision: **`samplerTier`** records which of
`TRACING_SAMPLER_RATELIMITING` / `_PROBABILISTIC` / `_CONST` is wired, by contract
priority, and is distinct from `samplerType` (the OTel sampler class). Node has no
native rate-limiting sampler, so a wired `TRACING_SAMPLER_RATELIMITING` goes into
`gaps` and L4 approximates it with a parent-based ratio.

For missing inspectable evidence, use `unknown` and record `gaps`.

## Output example

One `discovery-result` carrying every field listed in
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

Post the **L1 Discovery brief** — content and rules in common
[`reference/user-briefs.md`](../../opentelemetry-tracing-common/reference/user-briefs.md), Node additions in
[`../SKILL.md`](../SKILL.md) §3.1. Do not proceed to L2 until it is posted.
