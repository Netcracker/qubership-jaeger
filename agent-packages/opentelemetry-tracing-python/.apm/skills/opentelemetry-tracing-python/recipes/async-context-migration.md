# Recipe — async context migration (Python)

Fixes for Layer 4 §4.4 (`asyncContextMigration`) — see common
[`models/4-transformation.md`](../../opentelemetry-tracing-common/models/4-transformation.md)
§4.4.

**Input:** each context-loss candidate from `discovery-result.asyncBoundaries`
that remains `FAILED` in capability. **Goal:** one `trace_id` across the async
boundary; downstream span is a child of the upstream span.

Boundary signatures: [`../reference/detection-rules.md`](../reference/detection-rules.md)
§ Async-boundary signatures.

## asyncio (usually already fine)

`contextvars` propagate automatically across `await` and `asyncio.create_task`,
so the current OTel context follows a coroutine without extra work. Do **not**
add carriers here — treat plain `async`/`await` as `contextWrapper: true`. The
loss happens when you leave the event loop (below).

## Thread pools / executors

`ThreadPoolExecutor`, `loop.run_in_executor`, and raw `threading.Thread` do
**not** copy `contextvars` — the OTel context is lost. Capture the context and
re-attach it in the worker:

```python
from opentelemetry import context as otel_context

captured = otel_context.get_current()

def work():
    token = otel_context.attach(captured)
    try:
        with tracer.start_as_current_span("async-work"):
            ...
    finally:
        otel_context.detach(token)

executor.submit(work)
```

## Celery

Prefer `opentelemetry-instrumentation-celery` — it injects/extracts context
across the producer/worker boundary automatically. When instrumenting manually,
inject on publish and extract in the task before starting the span, so the task
span is a **child**, not a new root.

## Kafka

Prefer `opentelemetry-instrumentation-kafka-python` /
`opentelemetry-instrumentation-confluent-kafka`. For `aiokafka` or manual wiring:

```python
from opentelemetry.propagate import inject, extract
from opentelemetry import trace
from opentelemetry.trace import SpanKind

# producer — inject current context into record headers before send
carrier = {}
inject(carrier)  # default setter requires a dict carrier, not a list
# Kafka expects headers as a list of (key, bytes) tuples
headers = [(k, v.encode()) for k, v in carrier.items()]

# consumer — extract, then child span (not a new root)
# Kafka header values arrive as bytes; decode to str before extract
ctx = extract({k: v.decode() for k, v in (message.headers or [])})
with tracer.start_as_current_span("process " + topic, context=ctx, kind=SpanKind.CONSUMER):
    ...
```

**Common failure:** consumer span started without extracted parent → new root trace.
**Second failure:** B3 multi vs W3C `traceparent` mismatch — both sides must use
the same propagator configured for the service.

## HTTP async clients

Use the instrumentation for the client (`opentelemetry-instrumentation-httpx` /
`-requests` / `-aiohttp-client`), or inject manually before sending:

```python
from opentelemetry.propagate import inject

headers = {}
inject(headers)  # writes the configured formats
resp = await client.get(url, headers=headers)
```

## Validation

After the fix, run the Layer 5 runtime scenario: trigger HTTP → produce →
consume (when applicable) and confirm a single `trace_id` with correct
parent-child links in the tracing backend.
