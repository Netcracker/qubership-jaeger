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

| `service.framework` | §4.1 focus                                                                        |
|---------------------|-----------------------------------------------------------------------------------|
| `express`           | baseline + `@opentelemetry/instrumentation-http` + `-express`                      |
| `fastify`           | baseline + `@opentelemetry/instrumentation-http` + `-fastify`                      |
| `nestjs`            | baseline + `-nestjs-core` + `-http` + adapter (`-express`/`-fastify`)              |
| `pure-node`         | OTel SDK baseline modules only                                                     |
| `unknown`           | conservative baseline; record assumptions in `gaps`                                |

Framework and instrumentation signatures:
[`../reference/detection-rules.md`](../reference/detection-rules.md).

## Source-of-truth constraints

From the common platform contract
([`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)):

- preferred client library: OpenTelemetry SDK for Node.js;
- framework instrumentation is allowed only if it preserves platform requirements;
- Jaeger/OpenTracing/Zipkin client libraries are retired migration targets;
- OTLP is the recommended export format.

## Legacy → OTel moves

Applies to every framework stack when these are the active tracing dependencies:

- remove: `opentracing`, `jaeger-client`, `zipkin` / `zipkin-instrumentation-*`,
  the retired `@opentelemetry/exporter-jaeger`, and `@opentelemetry/exporter-zipkin`
  (when they form the active stack);
- add: `@opentelemetry/api`, the SDK, the OTLP proto exporter, and the B3
  propagator module (baseline below), plus the framework instrumentation packages
  from the table above.

## Target baseline modules

Required for `pure-node`, and as the SDK foundation for every framework path:

- `@opentelemetry/api`
- `@opentelemetry/sdk-node` (convenience) **or** `@opentelemetry/sdk-trace-node`
  (+ `@opentelemetry/resources`, `@opentelemetry/core`) for explicit control
- `@opentelemetry/exporter-trace-otlp-proto` (**http/protobuf — the contract encoding**)
- `@opentelemetry/propagator-b3`
- `@opentelemetry/semantic-conventions` (for `service.name` / resource attributes)

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
- OTel packages version-lock together — `@opentelemetry/api` is a peer of the SDK
  and instrumentation packages. Mixing an old `api` with a newer SDK/exporter
  raises peer-dependency warnings and runtime errors on moved symbols. Install
  them as one coherent set, let the package manager align them, and record the
  resolved set in the plan — never leave a split version set. If the service pins
  an old `@opentelemetry/api` for an unrelated reason, upgrade the whole OTel set
  together (or record an unresolvable conflict in `gaps`), never partially.
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
