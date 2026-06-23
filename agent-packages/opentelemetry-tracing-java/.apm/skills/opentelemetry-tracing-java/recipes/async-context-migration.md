# Recipe — async context migration

Concrete fixes for Layer 4 **§4.4** (`asyncContextMigration`) — see umbrella
[`models/4-transformation.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/models/4-transformation.md).
Addresses context-loss points from
`asyncBoundaries`. The goal: one `trace_id` across the async boundary, with
the downstream span a child of the upstream span.

## Kafka

Prefer OTel Kafka client instrumentation (or the agent) — it injects/extracts
headers automatically. Add it when the service uses plain Kafka clients and
auto-instrumentation is absent.

When clients are custom and bypass instrumentation, inject/extract manually:

```java
// producer — inject current context into record headers before send
TextMapSetter<Headers> setter = (carrier, key, value) ->
    carrier.add(key, value.getBytes(StandardCharsets.UTF_8));
ProducerRecord<String, String> record = new ProducerRecord<>(topic, payload);
openTelemetry.getPropagators().getTextMapPropagator()
    .inject(Context.current(), record.headers(), setter);
producer.send(record);
```

```java
// consumer — extract context, then start the span as a CHILD of it
TextMapGetter<Headers> getter = new TextMapGetter<>() {
  public Iterable<String> keys(Headers c) { /* header keys */ }
  public String get(Headers c, String key) {
    Header h = c.lastHeader(key);
    return h == null ? null : new String(h.value(), StandardCharsets.UTF_8);
  }
};
Context extracted = openTelemetry.getPropagators().getTextMapPropagator()
    .extract(Context.root(), record.headers(), getter);
Span span = tracer.spanBuilder("process " + topic)
    .setParent(extracted)
    .startSpan();
```

The most common failure is starting the consumer span **without** `setParent`,
producing a new root and a broken trace. The second is header-name mismatch
(B3 multi vs W3C `traceparent`) — both sides must use the same propagator.

## ExecutorService / thread pools

Wrap the executor so the submitting thread's context travels to the worker:

```java
Executor traced = Context.taskWrapping(rawExecutor);
```

## CompletableFuture

Capture the context and re-attach it inside the async stage:

```java
Context ctx = Context.current();
CompletableFuture.supplyAsync(() -> {
  try (Scope scope = ctx.makeCurrent()) {
    return doWork();
  }
}, traced);
```

## Reactor / Quarkus reactive

- Reactor: propagate via `contextWrite` and the OTel Reactor instrumentation;
  do not rely on `ThreadLocal` across `publishOn`/`subscribeOn`.
- Quarkus Reactive Messaging: enable the OTel extension; for manual `@Incoming`
  handlers, extract context from the incoming `Message` metadata and set it as
  the span parent, mirroring the Kafka consumer pattern.

## Verify

After the fix, run the Layer 5 runtime scenario: trigger HTTP → produce →
consume and confirm a single `trace_id` with correct parent-child links in the
Jaeger UI.
