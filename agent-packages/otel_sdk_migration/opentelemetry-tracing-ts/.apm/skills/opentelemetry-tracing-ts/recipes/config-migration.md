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
`${...}`, and never ship `undefined` either.

Set it via `OTEL_SERVICE_NAME` / `OTEL_RESOURCE_ATTRIBUTES=service.name=...` or a
programmatic resource:

```ts
import { resourceFromAttributes } from '@opentelemetry/resources';
import { ATTR_SERVICE_NAME } from '@opentelemetry/semantic-conventions';

const serviceName = process.env.MICROSERVICE_NAME;
const namespace = process.env.NAMESPACE; // Downward API, deployer, or the SA file

if (!serviceName || !namespace) {
  throw new Error('[tracing] MICROSERVICE_NAME and NAMESPACE must both resolve');
}

const resource = resourceFromAttributes({
  [ATTR_SERVICE_NAME]: `${serviceName}-${namespace}`, // resolved, not a template
});
```

### Kubernetes expands `$(VAR)`, not `${VAR}`

Composing the name in the manifest is fine, but only in the syntax Kubernetes
actually expands — `$(VAR)`, referencing a variable defined **earlier in the same
container's** `env` list. `${VAR}` is shell/Helm notation and reaches the process
verbatim:

```yaml
env:
  - name: MICROSERVICE_NAME
    value: order-service
  - name: NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
  - name: OTEL_SERVICE_NAME
    value: $(MICROSERVICE_NAME)-$(NAMESPACE)   # $(VAR) — not ${VAR}
```

### Honor `TRACING_ENABLED`

The contract switch has to reach the bootstrap, not only the chart. When it is off,
start nothing — no SDK, no exporter, no instrumentation registration:

```ts
if (process.env.TRACING_ENABLED === 'true') {
  // build the resource, construct NodeSDK, sdk.start()
}
```

A service that constructs the exporter regardless keeps retrying against an
endpoint nobody is listening on, and the logs read like a broken collector.

## Load order (the Node config that breaks silently)

The rule and the per-module-system forms:
[`../reference/build-preconditions.md`](../reference/build-preconditions.md)
§Load order; the loader-hook syntax to write:
[`../models/4-transformation.md`](../models/4-transformation.md) §ESM loader hook.
`--import` needs Node 18.19+/20.6+ — on an older major, plan the CommonJS `-r` form.

What makes it a **config** row: the fix lands in `package.json` `scripts.start`,
the Dockerfile `CMD`/`ENTRYPOINT`, and `NODE_OPTIONS` — not only in source. Emit a
row for whichever of those the deploy path actually uses.

## Propagation

The migration carries the configured wire format across and never switches it on
its own (common
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Propagation).

`OTEL_PROPAGATORS` and programmatic `propagation.setGlobalPropagator` are both
**runtime** in Node, so the format stays switchable without a recompile. Plan the
propagator on **one** surface: with both present the first registration wins and
the loser silently changes nothing ([`../models/1-discovery.md`](../models/1-discovery.md)
§1.2).

### Where to set it

Pass it to the SDK. That runs inside the SDK's own registration, so ordering can
never bite:

```ts
import { B3Propagator, B3InjectEncoding } from '@opentelemetry/propagator-b3';

const sdk = new NodeSDK({
  // b3multi: X-B3-* headers — required for the contract default
  textMapPropagator: new B3Propagator({ injectEncoding: B3InjectEncoding.MULTI_HEADER }),
});
sdk.start();
```

A standalone `propagation.setGlobalPropagator(...)` is only correct **before** the
SDK registers. After it, the plan row becomes a no-op that reads as configuration.

Always name the class **and its options**: a bare `new B3Propagator()` injects the
single `b3` header, so a row that says `b3multi` and ships it is wrong on the wire
while every end-to-end test passes. Verify the option against the
`@opentelemetry/propagator-b3` version in `package.json`.

### Composite membership and order

Which end of a composite wins on extract, and why inject is unaffected by order:
common [`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Propagation. Derive membership and the winning end from the user's intent
("B3 wins") — never ask which end wins, and never copy an order from another
service's config.

```ts
import { CompositePropagator, W3CTraceContextPropagator } from '@opentelemetry/core';
import { B3Propagator, B3InjectEncoding } from '@opentelemetry/propagator-b3';

// accepts traceparent AND X-B3-*; injects both on every outgoing request
const sdk = new NodeSDK({
  textMapPropagator: new CompositePropagator({
    propagators: [
      new W3CTraceContextPropagator(),
      new B3Propagator({ injectEncoding: B3InjectEncoding.MULTI_HEADER }),
    ],
  }),
});
```

If no propagator is configured, the SDK default is **W3C tracecontext + baggage**
— set the contract propagator explicitly rather than relying on that default.

## Sampling tiers

The contract wires one of three switches, in priority order **ratelimiting >
probabilistic > const**. Map the one that is set:

| Contract switch                 | Node target                                                                                             | 1:1     |
| ------------------------------- | ------------------------------------------------------------------------------------------------------- | ------- |
| `TRACING_SAMPLER_RATELIMITING`  | no native Node sampler — approximate with `parentbased_traceidratio` and record the deviation in `gaps` | no      |
| `TRACING_SAMPLER_PROBABILISTIC` | `OTEL_TRACES_SAMPLER=parentbased_traceidratio` + `OTEL_TRACES_SAMPLER_ARG=<ratio>`                      | yes     |
| `TRACING_SAMPLER_CONST`         | `1` → `parentbased_always_on`, `0` → `always_off`                                                       | partial |

Never leave the sampler unset and call it done: with nothing configured the SDK
default is `parentbased_always_on`, which samples everything in production.

## Endpoint filtering (probes and metrics)

The contract excludes probe and metrics endpoints from tracing. In Node this is a
config row on the HTTP instrumentation, not a framework setting:

```ts
import { HttpInstrumentation } from '@opentelemetry/instrumentation-http';

const EXCLUDED = [/^\/health/, /^\/metrics$/, /^\/prometheus$/, /^\/livez$/, /^\/readyz$/];

new HttpInstrumentation({
  ignoreIncomingRequestHook: (req) => {
    const path = (req.url ?? '').split('?')[0];
    return EXCLUDED.some((pattern) => pattern.test(path));
  },
});
```

Older `@opentelemetry/instrumentation-http` releases expose `ignoreIncomingPaths`
instead — check the installed version. The
`@opentelemetry/auto-instrumentations-node` meta package does **not** filter these
paths for you; the hook is still required under the `launcher` mechanism.

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

A `SimpleSpanProcessor` exports each span as it ends, which shortens the window but
does **not** remove it: the export itself is still an in-flight HTTP request, the
processor tracks unresolved exports, and its `forceFlush` awaits them. Await
`sdk.shutdown()` either way. Without it, end-to-end validation fails
intermittently — the trace is created but never arrives at the backend.

## Legacy config mappings

| From                                     | To                                         | 1:1     |
| ---------------------------------------- | ------------------------------------------ | ------- |
| `JAEGER_AGENT_HOST` (udp)                | `TRACING_HOST` + OTLP endpoint composition | no      |
| `JAEGER_AGENT_PORT` (6831)               | dropped — OTLP HTTP uses `4318`            | no      |
| `JAEGER_ENDPOINT` (collector)            | `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`       | no      |
| `tracing.enabled`                        | `TRACING_ENABLED`                          | yes     |
| `JAEGER_SAMPLER_PARAM`                   | `TRACING_SAMPLER_PROBABILISTIC` path       | partial |
| `ZIPKIN_ENDPOINT` / hardcoded Zipkin URL | OTLP endpoint from `TRACING_HOST`          | no      |

## Required target env shape

Shell/Helm notation — in a Kubernetes manifest use `$(VAR)` as shown above, and
make sure every referenced variable is defined earlier in the same container:

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

Emit **one** endpoint variable, in its own form: the signal-specific
`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` carries the full URL including `/v1/traces`
(above), while the generic `OTEL_EXPORTER_OTLP_ENDPOINT` is a base URL the exporter
appends to. Writing the path on the generic one yields a double `/v1/traces` and
silent export failure.

`OTEL_EXPORTER_OTLP_PROTOCOL` binds only when the exporter is auto-selected from
env; a hardcoded `new OTLPTraceExporter()` must be imported from
`@opentelemetry/exporter-trace-otlp-proto` instead
([`../reference/detection-rules.md`](../reference/detection-rules.md) §OTLP
exporter encoding).
