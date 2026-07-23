# Recipe — code migration (Python)

Concrete API rewrites for Layer 4 §4.3 (`codeMigration`).

Mechanical rewrites can be applied when safe; semantic attribute renames are
proposal-only.

## Legacy -> OTel examples

### OpenTracing span lifecycle -> OTel

```python
# before
span = opentracing.tracer.start_span("operation")
try:
    ...
finally:
    span.finish()

# after
tracer = trace.get_tracer(__name__)
with tracer.start_as_current_span("operation") as span:
    ...
```

### Jaeger client setup -> OTel SDK + OTLP

```python
# before — jaeger-client (udp/thrift to the agent)
from jaeger_client import Config
tracer = Config(config={...}, service_name="svc").initialize_tracer()

# after — OTel SDK exporting OTLP http/protobuf to the platform proxy
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter

provider = TracerProvider()  # resource with resolved service.name — see config-migration.md
provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(provider)
```

The exporter reads `OTEL_EXPORTER_OTLP_*` from the environment — keep endpoint and
protocol in config, not hardcoded (see [`config-migration.md`](config-migration.md)).

### Framework instrumentation (`instrumentor` path)

```python
# FastAPI (ASGI)
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
FastAPIInstrumentor.instrument_app(app)

# Flask (WSGI)
from opentelemetry.instrumentation.flask import FlaskInstrumentor
FlaskInstrumentor().instrument_app(app)

# Django (WSGI or ASGI) — in manage.py / wsgi.py / asgi.py, needs DJANGO_SETTINGS_MODULE set
from opentelemetry.instrumentation.django import DjangoInstrumentor
DjangoInstrumentor().instrument()
```

Do **not** combine these with the `opentelemetry-instrument` launcher for the same
app — pick one mechanism (Step 0b in [`../models/4-transformation.md`](../models/4-transformation.md)).

## Mechanical rewrite table

| Rule ID                     | Before                          | After                                       |
|-----------------------------|---------------------------------|---------------------------------------------|
| `startspan-to-tracer`       | `opentracing.tracer.start_span` | `tracer.start_as_current_span(name)`        |
| `finish-to-end`             | `span.finish()`                 | `span.end()` (or `with` block auto-ends)    |
| `set-tag-to-set-attribute`  | `span.set_tag(k, v)`            | `span.set_attribute(k, v)`                  |
| `jaeger-client-to-otel`     | `jaeger_client.Config`          | OTel `TracerProvider` + OTLP exporter       |
| `global-tracer-to-context`  | `opentracing.tracer` global use | `trace.get_tracer(__name__)` + current span |

## Semantic renames (proposal-only)

Attribute renames toward OpenTelemetry semantic conventions (e.g. custom
`http_path` → `http.route`, business keys) are **never** auto-applied. List them
in `codeMigration.semantic` and ask for confirmation (umbrella
[`models/4-transformation.md`](../../opentelemetry-tracing-umbrella/models/4-transformation.md)
§4.3).

## Guardrails

- Keep one active tracing stack.
- Preserve business/service naming intent.
- Never write secrets or unbounded payloads to span attributes.
