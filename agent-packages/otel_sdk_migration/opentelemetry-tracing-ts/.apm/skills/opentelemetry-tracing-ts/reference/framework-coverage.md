# Framework coverage (TypeScript / Node)

This list is the source of truth for which Node frameworks are first-class in this
package; the `service.framework` enum in
[`../schemas/L1-discovery-result.schema.json`](../schemas/L1-discovery-result.schema.json)
is this list plus `unknown`, and the two are extended together. Coverage is
extensible, not a hard gate: detection is signature-based, and a stack that is not
classified confidently falls back to `framework=unknown` plus the conservative SDK
path.

When a best-effort stack **is** identified confidently, prefer its matching
instrumentation over the bare SDK and record the stack and the choice in the plan
`gaps`, so a reviewer sees what was assumed.

Signatures for each stack live in [`detection-rules.md`](detection-rules.md)
§Framework signatures. **Confident** means a direct dependency in `package.json`
**and** a framework-construction symbol in source (`express()`, `Fastify()`,
`NestFactory.create`, `new Koa()`). A transitive dependency alone is not
confidence — a repository can carry `koa` under a dev tool without ever serving a
request through it.

## First-class framework stacks

- `express` (`@opentelemetry/instrumentation-express` + `-http`)
- `fastify` (`@fastify/otel` + `@opentelemetry/instrumentation-http`).
  `@opentelemetry/instrumentation-fastify` is **deprecated** — npm carries
  `Deprecated in favor of @fastify/otel, maintained by the Fastify authors` — so do
  not plan it. `@fastify/otel` is a Fastify **plugin**, not a monkey-patch
  instrumentation: register it with `await app.register(instr.plugin())`, or
  construct `new FastifyOtelInstrumentation({ registerOnInitialization: true })` and
  pass it in the `NodeSDK` `instrumentations` array. The `launcher` mechanism alone
  never wires it — see Step 0b.
- `nestjs` (`@opentelemetry/instrumentation-nestjs-core` + `-http` + the underlying
  HTTP adapter: `-express`, or `@fastify/otel` registered on the `FastifyAdapter`
  instance via `app.getHttpAdapter().getInstance()`)
- `pure-node` (worker, library, consumer, or a raw `http.Server`, with manual OTel
  SDK wiring). Add `@opentelemetry/instrumentation-http` whenever the process serves
  or calls `http`/`https`: it emits the SERVER span for a bare `http.createServer`
  and the CLIENT span for `http.request`. "No web framework" does not mean "no HTTP
  instrumentation".

Outbound `fetch()` needs its own instrumentation in **every** stack above. Node's
global `fetch` is undici, not the `http` module, so
`@opentelemetry/instrumentation-http` emits no client span for it and injects no
trace headers: the callee starts a new root trace while every exported span still
looks correct. Add `@opentelemetry/instrumentation-undici` whenever the service
calls peers with `fetch()`.

## Best-effort framework stacks

Detect these generically and keep `service.framework` at `unknown` — the schema enum
has no value for them. Record the identified stack in `gaps` as
`framework: <name> (best-effort)`, so the Step 0 `unknown` row can route to the
instrumentation named here instead of the bare SDK:

- Koa → `@opentelemetry/instrumentation-koa` (+ `-http`)
- Hapi → `@opentelemetry/instrumentation-hapi` (+ `-http`)
- Restify → `@opentelemetry/instrumentation-restify` (+ `-http`)
- Connect → `@opentelemetry/instrumentation-connect` (+ `-http`)
- GraphQL / Apollo Server → `@opentelemetry/instrumentation-graphql` (resolver
  spans; the HTTP span alone is one opaque `POST /graphql`)
- Socket.IO → `@opentelemetry/instrumentation-socket.io` (handlers run detached from
  the emitting scope — the `event-emitter` async boundary in §1.5)
- gRPC → `@opentelemetry/instrumentation-grpc` (instruments `@grpc/grpc-js`). gRPC
  is a transport, not a web framework: classify by the HTTP stack when there is one,
  and as `pure-node` when gRPC is the only server surface, then add `-grpc` on top.
  Reserve `unknown` for a server surface that is itself unclear.
- Next.js → no contrib instrumentation. Next registers OTel through its own
  `instrumentation.ts` hook (`@vercel/otel` or a hand-wired `NodeSDK`), **not**
  `-r`/`--import` — classify `unknown` and plan against that hook, or Step 0b picks
  a load mechanism the runtime ignores.
- Hono, Elysia, and other newer routers → no OTel instrumentation exists. Use the
  conservative SDK path plus `-http`, and say so in `gaps`.

## The auto-instrumentation meta package

`@opentelemetry/auto-instrumentations-node` enables about forty instrumentations at
once — the best-effort stacks above plus `-graphql`, `-undici`, `-socket.io`,
`-kafkajs` and the data clients — a valid `launcher`/`sdk` shortcut when the exact
per-library set is not worth enumerating. Three caveats before choosing it:

- it does **not** include Fastify (dropped after the contrib package was
  deprecated), so a Fastify or NestJS-on-Fastify service still needs `@fastify/otel`
  registered explicitly;
- `-dns` and `-net` are on by default in current releases, adding two spans per
  outbound call — check the `getNodeAutoInstrumentations` defaults for the version in
  `package.json`, and disable them unless that volume is wanted;
- it does not exclude probe and metrics endpoints; the contract's endpoint filtering
  still has to be wired through the `-http` `ignoreIncomingRequestHook`.

Subject to the Step 0b XOR and bundler guardrails in
[`../models/4-transformation.md`](../models/4-transformation.md).
