# Recipe — async context migration (Go)

Fixes for Layer 4 §4.4 (`asyncContextMigration`) — see umbrella
[`models/4-transformation.md`](../../opentelemetry-tracing-umbrella/models/4-transformation.md)
§4.4.

**Input:** each context-loss candidate from `discovery-result.asyncBoundaries`
that remains `FAILED` in capability. **Goal:** one `trace_id` across the async
boundary; downstream span is a child of the upstream span.

Boundary signatures: [`../reference/detection-rules.md`](../reference/detection-rules.md)
§ Async-boundary signatures.

## Goroutines / worker pools

- pass `context.Context` into goroutine entry;
- do not start child spans from `context.Background()` in async workers;
- if queue/worker strips context, add explicit context carrier.

```go
ctx := ctx // parent request/worker context
go func(ctx context.Context) {
    ctx, span := tracer.Start(ctx, "async-work")
    defer span.End()
    // work
}(ctx)
```

## Kafka

- inject trace headers on producer send;
- extract headers on consumer receive, then start child span with extracted parent;
- keep propagation format aligned (`b3multi` or chosen explicit format).

```go
// producer — inject current context into record headers before send
propagator.Inject(ctx, propagation.MapCarrier(headers))

// consumer — extract, then child span (not a new root)
ctx := propagator.Extract(context.Background(), propagation.MapCarrier(headers))
ctx, span := tracer.Start(ctx, "process "+topic, trace.WithSpanKind(trace.SpanKindConsumer))
defer span.End()
```

**Common failure:** consumer span started without extracted parent → new root trace.
**Second failure:** B3 multi vs W3C `traceparent` mismatch — both sides must use
the same propagator configured for the service.

## HTTP async clients

- use request context in outbound calls;
- ensure propagator injects headers before sending request.

```go
req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
propagator.Inject(ctx, propagation.HeaderCarrier(req.Header))
resp, err := httpClient.Do(req)
```

## Validation

After the fix, run the Layer 5 runtime scenario: trigger HTTP → produce →
consume (when applicable) and confirm a single `trace_id` with correct
parent-child links in the tracing backend.
