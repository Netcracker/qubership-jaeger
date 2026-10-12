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

## Standard `logging` — LogRecordFactory (recommended default)

Prefer a `LogRecordFactory` that **always** stamps the contract fields on every
record (empty outside a span). It is dependency-free, uses the contract names
directly (`traceId` / `spanId`), and — crucially — cannot make the formatter
throw, because the fields are always present:

```python
import logging
from opentelemetry import trace

_old_factory = logging.getLogRecordFactory()

def _factory(*args, **kwargs):
    record = _old_factory(*args, **kwargs)
    ctx = trace.get_current_span().get_span_context()
    record.traceId = format(ctx.trace_id, "032x") if ctx.is_valid else ""
    record.spanId = format(ctx.span_id, "016x") if ctx.is_valid else ""
    return record

logging.setLogRecordFactory(_factory)
logging.basicConfig(
    format="%(asctime)s %(levelname)s "
           "[traceId=%(traceId)s] [spanId=%(spanId)s] %(message)s",
)
```

A `logging.Filter` on the root handlers works too, but a factory is simpler
because it covers every record regardless of which handler emits it.

## Alternative — OTel LoggingInstrumentor (with a hard caveat)

`opentelemetry-instrumentation-logging` injects `otelTraceID`, `otelSpanID`, and
`otelServiceName` into `LogRecord`s. The injected field **names** are
`otelTraceID` / `otelSpanID`; the contract wants `traceId` / `spanId`, so map
them in the pattern:

```python
from opentelemetry.instrumentation.logging import LoggingInstrumentor

LoggingInstrumentor().instrument(set_logging_format=False)
logging.basicConfig(
    format="%(asctime)s %(levelname)s "
           "[traceId=%(otelTraceID)s] [spanId=%(otelSpanID)s] %(message)s",
)
```

> **Caveat — this format breaks log output for unstamped records.** A global
> format string that references `%(otelTraceID)s` raises `ValueError: Formatting
> field not found in record: 'otelTraceID'` (from an underlying `KeyError`) for
> **any** record the instrumentor did not stamp — third-party library loggers,
> the SDK's own export-retry warnings, or records created before `instrument()`
> ran. By default `logging` catches this in `handleError` (prints `--- Logging
> error ---` to stderr and drops the message), so the app does not crash — but
> that record's log line is lost. The factory above does not have this failure
> mode because it sets the fields on *every* record. If you use the instrumentor,
> verify no unstamped record ever hits that formatter.

`OTEL_PYTHON_LOG_CORRELATION=true` enables the auto path, but it only turns on
**injection** of the OTel `LogRecord` attributes (and, via `set_logging_format`,
the instrumentor's *default* format labelled `trace_id=`/`span_id=`) — it does **not**
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

## Validate

- generate request under active span;
- verify non-empty trace IDs in logs;
- match same trace ID in tracing backend.
