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

The package set per stack — including the Fastify plugin registration, the NestJS
adapter, and the `fetch()`/undici requirement that applies to every stack — is
[`../reference/framework-coverage.md`](../reference/framework-coverage.md). What
this gate adds is the **config surface** the plan must target:

| `service.framework`           | Config surface           |
| ----------------------------- | ------------------------ |
| `express`, `fastify`, `nestjs` | env + bootstrap module   |
| `pure-node`                   | env + programmatic setup |
| `unknown`                     | env; take the contrib instrumentation when `gaps` names a confident best-effort framework, otherwise the conservative SDK path, and record the assumption |

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
- **Name the mechanism explicitly — Node has three.** `launcher`, `sdk`, and
  `hand-spans`, defined in [`1-discovery.md`](1-discovery.md) §1.4. The plan states
  which one it targets.
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
- **Load order is non-negotiable**, and on ESM the `launcher` mechanism needs the
  loader hook **in addition to** `--import` — mechanics and why `--import` alone is
  not enough: [`../reference/build-preconditions.md`](../reference/build-preconditions.md)
  §Load order. The plan encodes the resulting entrypoint per `service.moduleSystem`
  **and** the chosen mechanism; the current form is §ESM loader hook below.
- **Bundler defeats monkey-patching.** When `service.bundled` is true, either
  externalize the instrumented dependencies or target `hand-spans`, and record the
  resolution in the plan —
  [`../reference/build-preconditions.md`](../reference/build-preconditions.md)
  §Bundling.
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

Check the plan carries every field in common
[`models/4-transformation.md`](../../opentelemetry-tracing-common/models/4-transformation.md) §Plan sections.
