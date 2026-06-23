# Recipe — code migration

Concrete API rewrites for Layer 4 **§4.3** (`codeMigration`) — see umbrella
[`models/4-transformation.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/models/4-transformation.md).
Mechanical rewrites are deterministic
and may be applied on confirmation; semantic attribute changes are proposals
only — see umbrella
[`models/4-transformation.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/models/4-transformation.md) §4.3.

## OpenTracing / Jaeger client → OTel

Imports:

```java
// before
import io.opentracing.Tracer;
import io.opentracing.util.GlobalTracer;
// after
import io.opentelemetry.api.OpenTelemetry;
import io.opentelemetry.api.trace.Span;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.api.trace.StatusCode;
import io.opentelemetry.context.Scope;
```

Span lifecycle:

```java
// before (OpenTracing)
Span span = tracer.buildSpan("operation").start();
try {
  // work
} finally {
  span.finish();
}

// after (OTel) — close in finally, record exceptions, set ERROR status
Span span = tracer.spanBuilder("operation").startSpan();
try (Scope scope = span.makeCurrent()) {
  // work
} catch (Exception e) {
  span.recordException(e);
  span.setStatus(StatusCode.ERROR);
  throw e;
} finally {
  span.end();
}
```

## Brave → OTel

Brave `span.tag(k, v)` → `span.setAttribute(k, v)`; obtain the tracer from the
injected `OpenTelemetry` (or framework-managed `Tracer`) instead of a Brave
`Tracing` bean. Remove the Brave `Tracing`/`Reporter` configuration class.

## Tracer acquisition

Prefer a framework-managed `OpenTelemetry`/`Tracer` (Spring bean, Quarkus CDI)
over `GlobalOpenTelemetry`. Build a manual `OpenTelemetrySdk` only for Pure
Java with no framework, once at startup.

```java
Tracer tracer = openTelemetry.getTracer("service-component");
```

## Mechanical rewrite table

| Rule id                    | Before                        | After                                                          |
|----------------------------|-------------------------------|----------------------------------------------------------------|
| `buildSpan-to-spanBuilder` | `tracer.buildSpan(n).start()` | `tracer.spanBuilder(n).startSpan()`                            |
| `finish-to-end`            | `span.finish()`               | `span.end()`                                                   |
| `tag-to-setAttribute`      | `span.tag(k, v)`              | `span.setAttribute(k, v)`                                      |
| `error-tag-to-status`      | `Tags.ERROR.set(span, true)`  | `span.setStatus(StatusCode.ERROR)` + `span.recordException(e)` |
| `globaltracer-to-otel`     | `GlobalTracer.get()`          | injected `OpenTelemetry.getTracer(...)`                        |

## Attributes

Use semantic-convention keys where they exist (see umbrella
[`models/4-transformation.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/models/4-transformation.md)
§4.3). Keep custom
attributes small, low-cardinality, and stable. Never record secrets, tokens,
full payloads, or unbounded values. Emit any business-key rename as a
**semantic** proposal, not a mechanical edit.
