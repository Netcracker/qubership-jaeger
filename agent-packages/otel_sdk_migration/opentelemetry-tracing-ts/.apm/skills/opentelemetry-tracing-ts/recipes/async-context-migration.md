# Recipe — async context migration (TypeScript / Node)

Fixes for Layer 4 §4.4 (`asyncContextMigration`) — see common
[`models/4-transformation.md`](../../opentelemetry-tracing-common/models/4-transformation.md)
§4.4.

**Input:** each context-loss candidate from `discovery-result.asyncBoundaries` that remains `FAILED` in capability.
**Goal:** one `trace_id` across the async boundary; downstream span is a child of the upstream span.
**Output:** one §4.4 row per fixed boundary — `{ boundary, fix }` plus `file` and
`line` when known. `boundary` reuses the value from `asyncBoundaries.type`
(`kafka-producer`, `kafka-consumer`, `worker-thread`, `child-process`,
`message-queue`, `event-emitter`, `http-client`, `other`), and `fix` names the
concrete mechanism applied below.

Boundary signatures: [`../reference/detection-rules.md`](../reference/detection-rules.md)
§ Async-boundary signatures.

**Every span opened by hand must end on every path.** `startActiveSpan` does not
end the span for you: a throw inside the callback leaks it, and the span is never
exported. Each snippet below closes in `finally` and records the error — keep that
shape when applying the fix.

## await / Promises / timers (usually already fine)

With the Node context manager (`AsyncLocalStorageContextManager`, registered by
`NodeSDK` / `NodeTracerProvider.register()`), OTel context follows `await`,
resolved Promises, `queueMicrotask`, `setTimeout`, and `setImmediate`
automatically. Do **not** add carriers here — plain `async`/`await` is not a loss
boundary. The loss happens when you leave the thread, the process, or the broker
(below).

**Setup check first:** if the provider is a `BasicTracerProvider` from
`@opentelemetry/sdk-trace-base` with no context manager, even `await` loses
context. Switch to `@opentelemetry/sdk-trace-node` / `NodeSDK` before adding
manual carriers.

## Worker threads

`worker_threads` run on a separate thread — `AsyncLocalStorage` does not cross the
boundary, and the worker is a **separate JS context that needs its own SDK
initialization** to create spans at all (init the tracing bootstrap inside the
worker entry too). Propagate context through the message channel: inject on the
main thread, extract in the worker before starting the span.

```ts
import { context, propagation, trace, SpanStatusCode } from '@opentelemetry/api';

// main thread — inject the active context into the worker message
const carrier: Record<string, string> = {};
propagation.inject(context.active(), carrier);
worker.postMessage({ carrier, payload });

// worker thread — after its own SDK bootstrap has run
const tracer = trace.getTracer('<service>');

const parentCtx = propagation.extract(context.active(), message.carrier);
context.with(parentCtx, () => {
  tracer.startActiveSpan('worker-task', (span) => {
    try {
      // ...
    } catch (err) {
      span.recordException(err as Error);
      span.setStatus({ code: SpanStatusCode.ERROR });
      throw err;
    } finally {
      span.end();
    }
  });
});
```

## Child processes

`child_process` `spawn`/`fork`/`exec` cross a process boundary. Use the same
inject/extract pattern, but pick the carrier by process lifetime:

- **short-lived `spawn`/`exec`** (one task, then exit) — env var or argv is fine;
  the context is valid for the whole life of that process;
- **long-lived `fork` worker** — carry the context in **each IPC message**, never in
  env. An env carrier is frozen at spawn time, so every span the child ever creates
  would attach to the first request's trace.

## Kafka

Prefer `@opentelemetry/instrumentation-kafkajs` — it injects/extracts context
across the producer/consumer boundary automatically. For manual wiring, note the
carrier type: **`kafkajs` delivers header values as `Buffer`**, and the propagators
silently ignore a non-string value — the consumer then starts a new root trace
while the code looks correct. Pass a getter that decodes them:

```ts
import {
  context, propagation, trace, SpanKind, SpanStatusCode, type TextMapGetter,
} from '@opentelemetry/api';

const tracer = trace.getTracer('<service>');

// kafkajs headers arrive as Buffer | string — decode before the propagator sees them
const kafkaHeaderGetter: TextMapGetter<Record<string, unknown>> = {
  keys: (carrier) => Object.keys(carrier ?? {}),
  get: (carrier, key) => {
    const value = carrier?.[key];
    return Buffer.isBuffer(value) ? value.toString('utf8') : (value as string | undefined);
  },
};

// producer — own span, inject inside it so the consumer parents to the send
await tracer.startActiveSpan(`send ${topic}`, { kind: SpanKind.PRODUCER }, async (span) => {
  try {
    const headers: Record<string, string> = {};
    propagation.inject(context.active(), headers);
    await producer.send({ topic, messages: [{ value, headers }] });
  } catch (err) {
    span.recordException(err as Error);
    span.setStatus({ code: SpanStatusCode.ERROR });
    throw err;
  } finally {
    span.end();
  }
});

// consumer — extract with the decoding getter, then a child span (not a new root)
const parentCtx = propagation.extract(context.active(), message.headers ?? {}, kafkaHeaderGetter);
await context.with(parentCtx, () =>
  tracer.startActiveSpan(`process ${topic}`, { kind: SpanKind.CONSUMER }, async (span) => {
    try {
      // ...
    } catch (err) {
      span.recordException(err as Error);
      span.setStatus({ code: SpanStatusCode.ERROR });
      throw err;
    } finally {
      span.end();
    }
  }),
);
```

**Common failure:** consumer span started without an extracted parent — either
because nothing was extracted, or because the carrier values were `Buffer` and the
propagator ignored them. Both look identical in the code and produce a new root
trace.

## Message queues / background jobs

`amqplib` (RabbitMQ), `bull`/`bullmq`, SQS, `nats` — same rule: inject the carrier
into the message (headers/metadata/job data) on publish, extract and open a child
span on consume. Prefer an OTel instrumentation for the library when one exists
(`@opentelemetry/instrumentation-amqplib`), else wire inject/extract manually as
above. Check the carrier type the client returns on consume, as with Kafka headers.

**Retries:** a carrier stored in job data (`bull`/`bullmq`) survives every retry, so
parenting each attempt to it collapses all attempts into the original trace. Parent
the first attempt and attach later attempts with a **span link** to the extracted
context instead, so each retry keeps its own trace and stays traceable back.

## HTTP async clients

Use the instrumentation for the client (`@opentelemetry/instrumentation-http`
covers `http`/`https`; `-undici` covers `fetch`/undici), or inject manually before
sending:

```ts
import { context, propagation } from '@opentelemetry/api';

const headers: Record<string, string> = {};
propagation.inject(context.active(), headers); // writes the configured formats
await fetch(url, { headers });
```

## EventEmitter

A listener that runs after the emitting async scope has exited loses context.
Capture and re-enter the context around the emit, or bind the listener:

```ts
import { context } from '@opentelemetry/api';
emitter.on('event', context.bind(context.active(), handler));
```

## Validation

After the fix, run the Layer 5 runtime scenario: trigger HTTP → produce → consume
(when applicable) and confirm a single `trace_id` with correct parent-child links
in the tracing backend.
