# Recipe — configuration migration (TypeScript / Node)

Concrete mappings for Layer 4 §4.2 (`configMigration`).

## Source of truth

Contracted parameters, export format, propagation, sampling, and service naming
come from the common platform contract
([`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md))
— do not restate or override them here.

### Service name and namespace (Node pitfall)

Build `service.name` from **resolved** values only. Reading a raw env template
(`process.env.OTEL_SERVICE_NAME ?? "${NAMESPACE}"`) or a Helm placeholder that was
never expanded ships a literal `${NAMESPACE}` into the resource attributes. Read
the namespace from an injected env var (`NAMESPACE` / `MICROSERVICE_NAMESPACE` via
Downward API or deployer), or from the mounted serviceaccount file
`/var/run/secrets/kubernetes.io/serviceaccount/namespace`, and compose
`${name}-${namespace}` at startup. Verify the resolved value — never ship a literal
`${...}`.

Set it via `OTEL_SERVICE_NAME` / `OTEL_RESOURCE_ATTRIBUTES=service.name=...` or a
programmatic resource:

```ts
import { resourceFromAttributes } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';

const resource = resourceFromAttributes({
  [ATTR_SERVICE_NAME]: `${serviceName}-${namespace}`, // resolved, not a template
});
```

## Load order (the Node config that breaks silently)

Tracing setup must run before instrumented modules load. Configure the entrypoint,
not just the code:

- **CommonJS:** `node -r ./tracing.js dist/main.js`, or `require('./tracing')` as
  the first statement of the entry file.
- **ESM:** `node --import ./tracing.mjs dist/main.js` (top-level
  `import './tracing.js'` is hoisted and runs too late) fixes load order. For the
  `launcher`/auto-instrumentation mechanism this is **not** sufficient by itself —
  monkey-patching wraps `require`, which ESM `import` bypasses — so also add
  `--experimental-loader=@opentelemetry/instrumentation/hook.mjs` alongside
  `--import` (both flags together, not either/or). `hand-spans` needs only
  `--import`.
- **Bundled:** externalize instrumented deps or use `hand-spans` — see
  [`../reference/build-preconditions.md`](../reference/build-preconditions.md).

This is a config/entrypoint change, not only source: update `package.json`
`scripts.start`, the Dockerfile `CMD`/`ENTRYPOINT`, and any `NODE_OPTIONS`.

## Propagation

**The migration preserves the wire format; it does not change it.** Carry the
configured inject format across, raise a conflict with the contract as a
**question** to the user, and on a greenfield service ask the user to pick
`B3` / `B3_MULTI` / `W3C` / a multi-format set instead of choosing silently
(common [`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Propagation).

`OTEL_PROPAGATORS` and programmatic `propagation.setGlobalPropagator` are both
**runtime** in Node — the format stays switchable without a recompile. If **both**
are present, the programmatic call wins — it overwrites the global propagator after
the SDK reads `OTEL_PROPAGATORS`. Treat the programmatic call as the source of
truth and record the env value as overridden.

### Name the class **and its options**, not just the format

`new B3Propagator()` **defaults to `B3InjectEncoding.SINGLE_HEADER`** — it injects
the **single** `b3` header. The contract `b3multi` (`X-B3-TraceId` /
`X-B3-SpanId` / `X-B3-Sampled`) requires the multi-header option explicitly:

```ts
import { propagation } from '@opentelemetry/api';
import { B3Propagator, B3InjectEncoding } from '@opentelemetry/propagator-b3';

// b3multi: X-B3-* headers — required for the contract default
propagation.setGlobalPropagator(
  new B3Propagator({ injectEncoding: B3InjectEncoding.MULTI_HEADER }),
);
```

A plan row that says "b3multi" and ships a bare `new B3Propagator()` is wrong on
the wire (single `b3`) while every end-to-end test still passes. Verify against the
`@opentelemetry/propagator-b3` version in `package.json`.

### Composite: extract is last-wins, inject writes everything

On **extract** `CompositePropagator` chains the context through each member in
order (a `reduce`), so the **last** member that finds a context wins — put the
format that should win last. On **inject** it loops every member so all formats
are written (each to its own carrier keys); inject order does not change which
formats are emitted. Derive membership and the winning end from the user's intent
("B3 wins") — do not ask which end wins, and do not copy an order from another
service's config.

```ts
import { propagation } from '@opentelemetry/api';
import { CompositePropagator, W3CTraceContextPropagator } from '@opentelemetry/core';
import { B3Propagator, B3InjectEncoding } from '@opentelemetry/propagator-b3';

// accepts traceparent AND X-B3-*; injects both on every outgoing request
propagation.setGlobalPropagator(
  new CompositePropagator({
    propagators: [
      new W3CTraceContextPropagator(),
      new B3Propagator({ injectEncoding: B3InjectEncoding.MULTI_HEADER }),
    ],
  }),
);
```

If no propagator is configured, the SDK default is **W3C tracecontext + baggage**
— set the contract propagator explicitly rather than relying on that default.

## Short-lived processes (CLI / one-shot job / worker / script)

A `BatchSpanProcessor` exports on a timer; a process that finishes and exits (a CLI
command, a one-shot Job, a script) can terminate **before** that flush, silently
dropping the spans it just created. The `pure-node` target — worker / CLI /
library / consumer — hits this routinely.

Flush on exit. Await SDK shutdown at the end of the unit of work, or on a signal:

```ts
process.on('SIGTERM', async () => {
  await sdk.shutdown(); // drains BatchSpanProcessor
  process.exit(0);
});
// or, at the end of a one-shot job:
await sdk.shutdown(); // (or provider.forceFlush())
```

For a very short process a `SimpleSpanProcessor` (synchronous export, nothing to
flush) is also acceptable. Without one of these, end-to-end validation fails
intermittently — the trace is created but never arrives at the backend.

## Legacy config mappings

| From                      | To                                         | 1:1     |
|---------------------------|--------------------------------------------|---------|
| `JAEGER_AGENT_HOST` (udp) | `TRACING_HOST` + OTLP endpoint composition | no      |
| `tracing.enabled`         | `TRACING_ENABLED`                          | yes     |
| `JAEGER_SAMPLER_PARAM`    | `TRACING_SAMPLER_PROBABILISTIC` path       | partial |
| hardcoded Zipkin URL      | OTLP endpoint from `TRACING_HOST`          | no      |

## Required target env shape

```text
TRACING_ENABLED=true|false
TRACING_HOST=nc-diagnostic-agent
TRACING_SAMPLER_PROBABILISTIC=0.01
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://${TRACING_HOST}:4318/v1/traces
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_PROPAGATORS=b3multi
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=${TRACING_SAMPLER_PROBABILISTIC}
OTEL_SERVICE_NAME=${MICROSERVICE_NAME}-${NAMESPACE}
```

`OTEL_PROPAGATORS=b3multi` above is the **contract default**, used only when the
service has no format configured and the user chose it. An existing format is
preserved instead — see §Propagation.

The Node OTLP HTTP exporter treats the two endpoint variables differently. The
signal-specific `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` is used **as-is** — give it
the full traces URL including `/v1/traces` (the form above). The generic
`OTEL_EXPORTER_OTLP_ENDPOINT` is a **base** URL — the exporter appends
`/v1/traces` itself, so it must **not** already contain the path. Pick one form —
putting `/v1/traces` on the generic variable produces a double `/v1/traces` path
and silent export failure.

`OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf` is honored only when the exporter is
auto-selected from env (`@opentelemetry/sdk-node` with no explicit exporter). If
the bootstrap does `new OTLPTraceExporter()`, import it from
`@opentelemetry/exporter-trace-otlp-proto` so the encoding matches the contract.
