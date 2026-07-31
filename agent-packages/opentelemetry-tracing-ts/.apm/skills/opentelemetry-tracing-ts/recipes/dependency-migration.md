# Recipe — dependency migration (TypeScript / Node)

Concrete moves for Layer 4 §4.1 (`dependencyMigration`) — see common
[`models/4-transformation.md`](../../opentelemetry-tracing-common/models/4-transformation.md)
§4.1.

Read versions from the target manifest (`package.json`, `package-lock.json`,
`yarn.lock`, `pnpm-lock.yaml`); do not hardcode versions here.

**Prerequisite:** complete TypeScript [`models/4-transformation.md`](../models/4-transformation.md)
Step 0 (framework stack) before emitting §4.1 rows — dependency moves follow
`discovery-result.service.framework`, not a free choice.

## Framework stack → dependency path

| `service.framework` | §4.1 focus                                                            |
| ------------------- | --------------------------------------------------------------------- |
| `express`           | baseline + `@opentelemetry/instrumentation-http` + `-express`         |
| `fastify`           | baseline + `@opentelemetry/instrumentation-http` + `@fastify/otel`    |
| `nestjs`            | baseline + `-nestjs-core` + `-http` + adapter (`-express` or `@fastify/otel`) |
| `pure-node`         | OTel SDK baseline + `-http` when the process serves or calls HTTP     |
| `unknown`           | if `gaps` carries `framework: <name> (best-effort)`, that framework's contrib instrumentation; otherwise conservative baseline. Record assumptions in `gaps` |

Add `@opentelemetry/instrumentation-undici` to **any** of the rows above when the
service calls peers with global `fetch()`: Node's `fetch` is undici, not the `http`
module, so `-http` emits no client span and injects no trace headers, and the trace
chain ends at this service while its own spans still look correct.

Add the messaging instrumentation for every `asyncBoundaries` entry the plan fixes
in §4.4 — `@opentelemetry/instrumentation-kafkajs` for kafka producers/consumers,
`@opentelemetry/instrumentation-amqplib` for RabbitMQ. §4.4 prefers these over
hand-rolled inject/extract, so §4.1 has to bring them in
([`async-context-migration.md`](async-context-migration.md)).

Framework and instrumentation signatures:
[`../reference/detection-rules.md`](../reference/detection-rules.md). Coverage and
best-effort stacks: [`../reference/framework-coverage.md`](../reference/framework-coverage.md).

## Source-of-truth constraints

From the common platform contract
([`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)):

- preferred client library: OpenTelemetry SDK for Node.js;
- framework instrumentation is allowed only if it preserves platform requirements;
- Jaeger/OpenTracing/Zipkin client libraries are retired migration targets;
- OTLP is the recommended export format.

## Legacy → OTel moves

Applies to every framework stack when these are the active tracing dependencies:

- remove: `opentracing`, `jaeger-client`, `zipkin` / `zipkin-instrumentation-*` /
  `zipkin-transport-*`, the retired `@opentelemetry/exporter-jaeger`, and
  `@opentelemetry/exporter-zipkin` (when they form the active stack);
- remove non-OTel APM agents (`dd-trace`, `elastic-apm-node`, `newrelic`) **only
  when the agent is the active tracing stack**. An agent kept for metrics or
  profiling stays, but record the double-instrumentation risk in `gaps` — two
  agents patching the same libraries can duplicate or drop spans;
- replace the deprecated `@opentelemetry/instrumentation-fastify` with
  `@fastify/otel` on any Fastify or NestJS-on-Fastify service. The replacement is a
  Fastify **plugin**, so §4.3 must also add its registration — the launcher never
  wires it ([`../reference/framework-coverage.md`](../reference/framework-coverage.md));
- add: `@opentelemetry/api`, the SDK, the OTLP proto exporter, and the B3
  propagator module (baseline below), plus the framework instrumentation packages
  from the table above.

After editing `package.json`, run one ordinary install (`npm install` / `yarn
install` / `pnpm install`) and commit the refreshed lockfile. The L5 gate runs a
**frozen** install (`npm ci` and friends), which fails on exactly the drift these
rows create ([`fresh-build-and-image.md`](fresh-build-and-image.md)).

In a workspace repository the dependencies belong to the **service's** manifest,
not the repository root — a root-level entry can be hoisted away when the image is
built from a pruned subtree.

## Target baseline modules

Required for `pure-node`, and as the SDK foundation for every framework path:

- `@opentelemetry/api`
- `@opentelemetry/sdk-node` (convenience) **or** `@opentelemetry/sdk-trace-node`
  (+ `@opentelemetry/resources`, `@opentelemetry/core`) for explicit control
- `@opentelemetry/exporter-trace-otlp-proto` (**http/protobuf — the contract encoding**)
- `@opentelemetry/propagator-b3`
- `@opentelemetry/semantic-conventions` (for `service.name` / resource attributes)
- `@opentelemetry/instrumentation` — only for the `sdk` mechanism, which imports
  `registerInstrumentations` from it directly. It also arrives transitively with any
  `-instrumentation-*` package, but a direct import from a transitive dependency
  breaks on dedupe and on `import/no-extraneous-dependencies`

Pick the exporter package deliberately: `@opentelemetry/exporter-trace-otlp-http`
sends **JSON**, `@opentelemetry/exporter-trace-otlp-grpc` sends gRPC — use
`-otlp-proto` for the contract `http/protobuf`, and `-otlp-grpc` only when the
environment explicitly requires gRPC OTLP.

Use `@opentelemetry/sdk-trace-node` (not `@opentelemetry/sdk-trace-base`
`BasicTracerProvider`) so the `AsyncLocalStorageContextManager` is registered —
without the Node context manager, context is lost across `await`.

Zero-code auto-instrumentation (optional, chosen at Step 0b — **not** alongside a
programmatic `registerInstrumentations()` for the same library):

- `@opentelemetry/auto-instrumentations-node` (bundles common web/DB/messaging
  instrumentations; used via the `-r`/`--import` launcher or
  `getNodeAutoInstrumentations()` in a programmatic bootstrap)

## Manifest guardrails

- Keep the tracing packages in **`dependencies`**, not `devDependencies` — they
  must be present in the built/installed image at runtime. (Type-only `@types/*`
  packages stay in `devDependencies`.)
- **OTel JS ships two version tracks — align within each, never across.** The
  stable track (`@opentelemetry/api`, `sdk-trace-node`, `sdk-trace-base`,
  `resources`, `core`, `semantic-conventions`) carries 1.x/2.x numbers; the
  experimental track (`sdk-node`, every `exporter-*`, `instrumentation`, every
  `instrumentation-*`, `auto-instrumentations-node`) carries a shared `0.x` number
  released in lockstep. At the time of writing that is `api` 1.9.x and
  `sdk-trace-node`/`resources`/`core` 2.x against `sdk-node`/exporters/
  instrumentations 0.221.x — read the actual numbers from the manifest, never these.
  All packages **inside** one track move together; the two tracks legitimately show
  different numbers, so a `0.x` next to a `2.x` is not a split.
- The **majors do matter across tracks** because APIs moved with them:
  `@opentelemetry/resources` 2.x exposes `resourceFromAttributes(...)`, 1.x has only
  `new Resource(...)` and the 2.x snippet fails with `resourceFromAttributes is not
  a function`. Record the resolved majors in the plan so §4.3 picks the matching
  code shape.
- `@opentelemetry/api` is a peer of both tracks. Mixing an old `api` with a newer
  SDK/exporter raises peer-dependency warnings and runtime errors on moved symbols.
  If the service pins an old `api` for an unrelated reason, upgrade the whole OTel
  set together (or record an unresolvable conflict in `gaps`), never partially.
- **Coherence overrides "defer versions" on a split.** [`SKILL.md`](../SKILL.md)
  *Defer versions* forbids **inventing** version numbers — not constraining a
  broken resolution back to coherence. Default: don't pin, let the resolver align.
  But if it yields a split (mismatched `@opentelemetry/*` release lines, or a peer
  warning that `@opentelemetry/api` is unmet), pin the **whole** OTel stack to
  **one** coherent set taken from the resolution already produced (e.g. the
  `api`/`sdk` versions, not invented ones) and record the pinned set.
- Keep a **single** `@opentelemetry/api` in the tree — a duplicated `api` (two
  copies in `node_modules` from mismatched ranges) silently splits the global
  tracer/propagator so instrumentation and app code use different registries. Dedupe
  (`npm dedupe` / a `resolutions`/`overrides` entry) when detected.
