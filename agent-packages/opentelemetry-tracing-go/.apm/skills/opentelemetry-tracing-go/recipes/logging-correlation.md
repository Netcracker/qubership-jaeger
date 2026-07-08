# Recipe — trace IDs in logs (Go)

Adding `traceId`/`spanId` to logs is mandatory.

Expected shape:

```text
... [traceId=<value>] [spanId=<value>] ...
```

## Rule

1. First check whether the project's logging setup already emits these fields.
2. If not, add logger integration that injects current span context into log fields.
3. Keep field names stable: `traceId`, `spanId`.

Registering a `TracerProvider` does **not** wire the logging bridge by itself:
spans reaching the backend prove export, not log correlation. Always verify the
fields in actual log output as a separate check.

## Validate

- generate request under active span;
- verify non-empty trace IDs in logs;
- match same trace ID in tracing backend.
