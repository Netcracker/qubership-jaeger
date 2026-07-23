# Recipe — trace IDs in logs (Python)

Adding `traceId`/`spanId` to logs is mandatory.

Expected shape:

```text
... [traceId=<value>] [spanId=<value>] ...
```

## Rule

1. First check whether the project's logging setup already emits these fields.
2. If not, wire the current span context into log records.
3. Keep field names stable in the output: `traceId`, `spanId`.

## Standard `logging` — OTel LoggingInstrumentor

`opentelemetry-instrumentation-logging` injects `otelTraceID`, `otelSpanID`, and
`otelServiceName` into every `LogRecord`. Enable it and reference the fields in
the format string. Note the injected field **names** are `otelTraceID` /
`otelSpanID`; the contract wants `traceId` / `spanId`, so map them in the pattern:

```python
from opentelemetry.instrumentation.logging import LoggingInstrumentor

LoggingInstrumentor().instrument(set_logging_format=False)
logging.basicConfig(
    format="%(asctime)s %(levelname)s "
           "[traceId=%(otelTraceID)s] [spanId=%(otelSpanID)s] %(message)s",
)
```

`OTEL_PYTHON_LOG_CORRELATION=true` enables the auto path, but it only turns on
**injection** of the OTel `LogRecord` attributes (and, via `set_logging_format`,
the SDK's *default* format labelled `trace_id=`/`span_id=`) — it does **not**
produce the contract shape `[traceId=…] [spanId=…]`. Set the contract format
string explicitly even on the auto path.

## structlog / JSON loggers

Add a processor that reads the current span context and emits stable keys:

```python
from opentelemetry import trace

def add_trace_ids(logger, method, event_dict):
    ctx = trace.get_current_span().get_span_context()
    if ctx.is_valid:
        event_dict["traceId"] = format(ctx.trace_id, "032x")
        event_dict["spanId"] = format(ctx.span_id, "016x")
    return event_dict
```

Registering a `TracerProvider` does **not** wire log correlation by itself: spans
reaching the backend prove export, not correlation. Always verify the fields in
actual log output as a separate check.

## Validate

- generate request under active span;
- verify non-empty trace IDs in logs;
- match same trace ID in tracing backend.
