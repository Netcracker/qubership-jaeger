# Recipe — async context migration (TypeScript / Node)

Fixes for Layer 4 §4.4 (`asyncContextMigration`) — see common
[`models/4-transformation.md`](../../opentelemetry-tracing-common/models/4-transformation.md)
§4.4.

**Input:** each context-loss candidate from `discovery-result.asyncBoundaries` that remains `FAILED` in capability.
**Goal:** one `trace_id` across the async boundary; downstream span is a child of the upstream span.

Boundary signatures: [`../reference/detection-rules.md`](../reference/detection-rules.md)
§ Async-boundary signatures.

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
import { context, propagation, trace } from '@opentelemetry/api';

// main thread — inject the active context into the worker message
const carrier: Record<string, string> = {};
propagation.inject(context.active(), carrier);
worker.postMessage({ carrier, payload });

// worker thread — extract, then child span (not a new root)
const ctx = propagation.extract(context.active(), message.carrier);
context.with(ctx, () => {
  tracer.startActiveSpan('worker-task', (span) => {
    // ...
    span.end();
  });
});
```

## Child processes

`child_process` `spawn`/`fork`/`exec` cross a process boundary. Pass the carrier
through env/argv/IPC message and extract in the child, same inject/extract pattern
as worker threads.

## Kafka

Prefer `@opentelemetry/instrumentation-kafkajs` — it injects/extracts context
across the producer/consumer boundary automatically. For manual wiring:

```ts
import { context, propagation, trace, SpanKind } from '@opentelemetry/api';

// producer — inject current context into message headers before send
const headers: Record<string, string> = {};
propagation.inject(context.active(), headers);
await producer.send({ topic, messages: [{ value, headers }] });

// consumer — extract, then child span (not a new root)
const ctx = propagation.extract(context.active(), message.headers ?? {});
await context.with(ctx, () =>
  tracer.startActiveSpan(`process ${topic}`, { kind: SpanKind.CONSUMER }, async (span) => {
    // ...
    span.end();
  }),
);
```

**Common failure:** consumer span started without extracted parent → new root trace.

## Message queues / background jobs

`amqplib` (RabbitMQ), `bull`/`bullmq`, SQS, `nats` — same rule: inject the carrier
into the message (headers/metadata/job data) on publish, extract and open a child
span on consume. Prefer an OTel instrumentation for the library when one exists
(`@opentelemetry/instrumentation-amqplib`), else wire inject/extract manually as
above.

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
