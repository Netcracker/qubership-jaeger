# Recipe — runtime validation stack — Go delta

Preconditions, topology, platform env, minimal install, runtime order, and teardown:
[`opentelemetry-tracing-common/recipes/validation-stack.md`](../../opentelemetry-tracing-common/recipes/validation-stack.md).

Go specifics below.

## Propagation assert

The wire-header assert matters most in Go: `b3.New()` with no options injects the single `b3` header, not `X-B3-*`, so
a plan that says `b3multi` can ship a service that emits `b3`. Confirm the constructor carries
`b3.WithInjectEncoding(b3.B3MultipleHeader)` and then confirm the headers on the wire.

## No spans in the backend — Go checks first

1. **Provider never registered globally.** A `TracerProvider` built but not passed to `otel.SetTracerProvider` leaves
   every `otel.Tracer(...)` call on the no-op provider — the code compiles and produces nothing.
2. **Context not threaded.** A handler that starts a span from `context.Background()` instead of the request context
   produces a detached root per call, so the spans exist but never join a trace.
3. **Exporter shutdown missing.** A short-lived process that exits without `TracerProvider.Shutdown(ctx)` drops the
   batch still in the queue.

Then continue with the shared list.
