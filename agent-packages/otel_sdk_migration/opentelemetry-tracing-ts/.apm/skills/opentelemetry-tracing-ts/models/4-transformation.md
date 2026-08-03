# Layer 4 — Transformation (TypeScript / Node)

Shared plan structure, algorithm, and section numbering (§4.1–§4.5):
[`opentelemetry-tracing-common/models/4-transformation.md`](../../opentelemetry-tracing-common/models/4-transformation.md).

Run the **TypeScript gate below before §4.1**. Then fill §4.1–§4.4 from recipes:

| Section                      | Recipe                                                                                                                                        |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| §4.1 `dependencyMigration`   | [`../recipes/dependency-migration.md`](../recipes/dependency-migration.md)                                                                    |
| §4.2 `configMigration`       | [`../recipes/config-migration.md`](../recipes/config-migration.md) + [`../recipes/logging-correlation.md`](../recipes/logging-correlation.md) |
| §4.3 `codeMigration`         | [`../recipes/code-migration.md`](../recipes/code-migration.md)                                                                                |
| §4.4 `asyncContextMigration` | [`../recipes/async-context-migration.md`](../recipes/async-context-migration.md)                                                              |

§4.5 `validationPlan` is mandatory on every plan, including a plan-only document —
TypeScript specifics in [`5-validation.md`](5-validation.md).

## Step 0 — Framework stack decision (mandatory)

**Framework stack** = how the service serves requests (from L1 →
`service.framework` in `discovery-result.json`): Express, Fastify, NestJS, or a
non-web worker/library — not "one repository = one stack" by default.

Read `discovery-result.service.framework` and pick exactly one migration path.
Do not emit §4.1 or §4.2 rows before this is fixed.

| `service.framework` | Target instrumentation                                                                                                                                                                                                                         | Config surface           |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| `express`           | `@opentelemetry/instrumentation-http` + `-express` + SDK + OTLP proto + B3 propagator                                                                                                                                                          | env + bootstrap module   |
| `fastify`           | `@opentelemetry/instrumentation-http` + `@fastify/otel` + SDK + OTLP proto + B3 (**not** the deprecated `-fastify`)                                                                                                                            | env + bootstrap module   |
| `nestjs`            | `@opentelemetry/instrumentation-nestjs-core` + `-http` + the underlying HTTP adapter (`-express`, or `@fastify/otel` on the `FastifyAdapter`) + SDK                                                                                            | env + bootstrap module   |
| `pure-node`         | `@opentelemetry/sdk-node` (or `sdk-trace-node`) + OTLP proto exporter + B3 propagator, plus `-http` when the process serves or calls HTTP (no web-framework middleware)                                                                        | env + programmatic setup |
| `unknown`           | if `gaps` names a confidently identified best-effort framework, its contrib instrumentation from [`../reference/framework-coverage.md`](../reference/framework-coverage.md); otherwise the conservative SDK path. Record assumptions in `gaps` | env                      |

NestJS runs on Express or Fastify underneath: `-nestjs-core` alone gives
controller/provider spans but **not** the HTTP server span — add the HTTP
instrumentation and the matching adapter instrumentation.

`@fastify/otel` is a Fastify **plugin**, so it is not wired by the launcher: register
it on the app (`await app.register(instr.plugin())`) or pass
`new FastifyOtelInstrumentation({ registerOnInitialization: true })` in the `NodeSDK`
`instrumentations` array. A Fastify plan whose mechanism is `launcher` and that names
no explicit registration produces HTTP spans and no route spans. Outbound `fetch()`
also needs `@opentelemetry/instrumentation-undici` — `-http` does not cover it. See
[`../reference/framework-coverage.md`](../reference/framework-coverage.md).

Pull versions from the repository manifest (`package.json`/lockfile); never pin
in the plan.

## Step 0b — Instrumentation-mechanism guardrails (mandatory)

Read `instrumentation.mechanism` and `instrumentation.hook` from
`discovery-result.json` — that is the **current** state. The plan states the
**target** mechanism and hook and, when they differ, why. `mechanism: unknown`
means L1 saw a launcher / `registerInstrumentations` conflict: resolve the XOR
below before emitting any §4.1 row.

After the framework stack is chosen, validate the **mechanism**. Pick **one** and
reject the forbidden combinations in the plan:

- **End with one active tracing stack.** Remove Zipkin/OpenTracing/Jaeger client
  as active tracing stacks.
- **Name the mechanism explicitly — Node has three.** `launcher` (the zero-code
  `@opentelemetry/auto-instrumentations-node/register` loaded via `-r`/`--require`
  or `NODE_OPTIONS`/ESM `--import`, auto-instruments every detected library at
  startup), `sdk` (a programmatic bootstrap that constructs `NodeSDK` /
  `NodeTracerProvider` and calls `registerInstrumentations({...})` /
  `getNodeAutoInstrumentations()`), and `hand-spans` (spans written by hand with
  `startActiveSpan`). The plan states which one it targets.
- **`pure-node` → the launcher still applies when the process uses instrumented
  libraries.** `auto-instrumentations-node` covers messaging and data clients
  (kafkajs, amqplib, pg, MySQL, MongoDB, redis/ioredis, the HTTP client), so a
  consumer or a worker gets those spans zero-code. The launcher adds nothing only
  when the process has no instrumented I/O at all — a CPU-bound CLI or a library.
  Target `sdk` or `hand-spans` there, and whenever the units of work themselves
  need spans. The guardrails hold either way: one active stack, platform contract,
  correct exporter package, and (for a short-lived process) flush on exit — see
  [`../recipes/config-migration.md`](../recipes/config-migration.md)
  §Short-lived processes.
- **`launcher` XOR programmatic `registerInstrumentations` for the same library.**
  Do **not** run the launcher *and* call `registerInstrumentations()` for the same
  library — double-registration can duplicate spans. Choose `launcher` **or** the
  programmatic `sdk` path.
- **Load order is non-negotiable.** The tracing bootstrap must run **before** any
  instrumented module is loaded. In **CommonJS**, `require('./tracing')` as the
  first line (or `node -r ./tracing.js`) works. In **ESM**, a top-level
  `import './tracing.js'` does **not** — ESM hoists all `import`s in a module, so
  the instrumented libraries may be evaluated before the bootstrap runs; use
  `node --import ./tracing.mjs` instead. `--import` alone fixes only the *load
  order* (the SDK initializes first). It does **not** make the launcher's
  monkey-patch instrumentation able to wrap ESM modules — CJS patching relies on
  overriding `require`, which ESM `import` never goes through. For the `launcher`
  mechanism on ESM, add `--experimental-loader=@opentelemetry/instrumentation/hook.mjs`
  **in addition to** `--import`, not instead of it: `node
  --experimental-loader=@opentelemetry/instrumentation/hook.mjs --import
  ./tracing.mjs dist/main.mjs` — but see the `register()` form below, which is the
  current one. The `hand-spans` mechanism needs only `--import` (there is nothing
  to monkey-patch). Encode this in the plan per `service.moduleSystem` **and** the
  chosen mechanism.
- **Bundler defeats monkey-patching.** If `service.bundled` is true, a bundler
  (esbuild/webpack/rollup/tsup/ncc) inlines `require`/`import`, so the
  instrumentation packages have nothing to patch at runtime. Either externalize
  the instrumented dependencies from the bundle (mark them external / keep them in
  `node_modules`) or target `hand-spans`. Record the chosen resolution in the plan
  — see [`../reference/build-preconditions.md`](../reference/build-preconditions.md).
- **Correct OTLP exporter package.** For the contract `http/protobuf` use
  `@opentelemetry/exporter-trace-otlp-proto`. `-otlp-http` (JSON) and `-otlp-grpc`
  are not the contract format — do not substitute silently.
- **Preserve the platform contract** (`TRACING_*`, OTLP, propagation, sampling)
  regardless of mechanism.

### ESM loader hook: prefer `register()` on Node 20.6+

Node warns that `--experimental-loader` may be removed and points at `register()`
from `node:module`. On Node 20.6 and newer, plan the launcher hook this way:

```shell
node --import ./tracing.mjs dist/main.mjs
```

with the bootstrap registering the hook itself before it configures the SDK:

```ts
import { register } from 'node:module';

register('@opentelemetry/instrumentation/hook.mjs', import.meta.url);
```

Keep the `--experimental-loader` form only for runtimes older than 20.6. Either
way the entrypoint changes, so the chosen form is a plan row — record it in
`configMigration` with the file that owns the command (`package.json` `scripts`,
Dockerfile `CMD`, or Helm `command`/`args`).

Validate result against
[`../../opentelemetry-tracing-common/schemas/L4-migration-plan.schema.json`](../../opentelemetry-tracing-common/schemas/L4-migration-plan.schema.json).
