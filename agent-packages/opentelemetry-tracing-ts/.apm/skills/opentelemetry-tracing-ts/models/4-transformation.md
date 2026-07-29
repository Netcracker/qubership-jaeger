# Layer 4 — Transformation (TypeScript / Node)

Shared plan structure, algorithm, and section numbering (§4.1–§4.5):
[`opentelemetry-tracing-common/models/4-transformation.md`](../../opentelemetry-tracing-common/models/4-transformation.md).

Run the **TypeScript gate below before §4.1**. Then fill §4.1–§4.4 from recipes:

| Section                      | Recipe                                                                                                                                        |
|------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| §4.1 `dependencyMigration`   | [`../recipes/dependency-migration.md`](../recipes/dependency-migration.md)                                                                    |
| §4.2 `configMigration`       | [`../recipes/config-migration.md`](../recipes/config-migration.md) + [`../recipes/logging-correlation.md`](../recipes/logging-correlation.md) |
| §4.3 `codeMigration`         | [`../recipes/code-migration.md`](../recipes/code-migration.md)                                                                                |
| §4.4 `asyncContextMigration` | [`../recipes/async-context-migration.md`](../recipes/async-context-migration.md)                                                              |

## Step 0 — Framework stack decision (mandatory)

**Framework stack** = how the service serves requests (from L1 →
`service.framework` in `discovery-result.json`): Express, Fastify, NestJS, or a
non-web worker/library — not "one repository = one stack" by default.

Read `discovery-result.service.framework` and pick exactly one migration path.
Do not emit §4.1 or §4.2 rows before this is fixed.

| `service.framework` | Target instrumentation                                                                                          | Config surface              |
|---------------------|----------------------------------------------------------------------------------------------------------------|-----------------------------|
| `express`           | `@opentelemetry/instrumentation-http` + `-express` + SDK + OTLP proto + B3 propagator                           | env + bootstrap module      |
| `fastify`           | `@opentelemetry/instrumentation-http` + `-fastify` + SDK + OTLP proto + B3                                      | env + bootstrap module      |
| `nestjs`            | `@opentelemetry/instrumentation-nestjs-core` + `-http` + the underlying HTTP adapter (`-express`/`-fastify`) + SDK | env + bootstrap module      |
| `pure-node`         | `@opentelemetry/sdk-node` (or `sdk-trace-node`) + OTLP proto exporter + B3 propagator (no web middleware)       | env + programmatic setup    |
| `unknown`           | conservative SDK path; record assumptions in `gaps`                                                             | env                         |

NestJS runs on Express or Fastify underneath: `-nestjs-core` alone gives
controller/provider spans but **not** the HTTP server span — add the HTTP
instrumentation and the matching adapter instrumentation.

Pull versions from the repository manifest (`package.json`/lockfile); never pin
in the plan.

## Step 0b — Instrumentation-mechanism guardrails (mandatory)

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
- **`pure-node` → mechanism is `sdk` or `hand-spans`.** With no web framework the
  launcher's framework hooks have nothing to attach to; wire the SDK
  programmatically and/or instrument the units of work by hand with
  `startActiveSpan`. The guardrails that still apply are one active stack,
  platform contract, correct exporter package, and (for a short-lived process)
  flush on exit — see [`../recipes/config-migration.md`](../recipes/config-migration.md)
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
  ./tracing.mjs dist/main.mjs`. The `hand-spans` mechanism needs only `--import`
  (there is nothing to monkey-patch). Encode this in the plan per
  `service.moduleSystem` **and** the chosen mechanism.
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

Validate result against
[`../schemas/L4-migration-plan.schema.json`](../schemas/L4-migration-plan.schema.json).
