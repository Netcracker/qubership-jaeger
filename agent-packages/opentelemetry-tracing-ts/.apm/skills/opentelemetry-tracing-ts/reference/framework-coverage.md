# Framework coverage (TypeScript / Node)

This list is the **single source of truth** for which Node frameworks are
first-class in this package; the `service.framework` schema enum mirrors it.
Treat it as extensible coverage, not a hard gate — detection is generic
(signature-based), and anything not confidently classified falls back to
`unknown` + the conservative SDK path. Extend the first-class set here (and the
schema enum) when a repository shows a framework is common in practice.

First-class framework stacks for this package:

- `express` (`@opentelemetry/instrumentation-express` + `-http`)
- `fastify` (`@opentelemetry/instrumentation-fastify` + `-http`)
- `nestjs` (`@opentelemetry/instrumentation-nestjs-core` + `-http` + the
  underlying HTTP adapter instrumentation `-express` or `-fastify`)
- `pure-node` (worker/library/consumer/`http.Server` with manual OTel SDK wiring)

Best-effort framework stacks (detect generically; emit `framework=unknown` unless
a confident match is possible). When a best-effort framework **is** confidently
identified, prefer its matching OTel contrib instrumentation over the bare SDK:

- Koa → `@opentelemetry/instrumentation-koa` (+ `-http`)
- Hapi → `@opentelemetry/instrumentation-hapi` (+ `-http`)
- Restify → `@opentelemetry/instrumentation-restify` (+ `-http`)
- Connect → `@opentelemetry/instrumentation-connect` (+ `-http`)
- gRPC services → `@opentelemetry/instrumentation-grpc`

The `@opentelemetry/auto-instrumentations-node` meta package bundles the common
web/DB/messaging instrumentations at once — a valid `launcher`/`sdk` shortcut when
the exact per-library set is not worth enumerating, subject to the Step 0b XOR and
bundler guardrails.

Only when no matching instrumentation exists, or the framework cannot be
identified with confidence, fall back to `framework=unknown` and the conservative
SDK migration path plus a `gaps` note.
