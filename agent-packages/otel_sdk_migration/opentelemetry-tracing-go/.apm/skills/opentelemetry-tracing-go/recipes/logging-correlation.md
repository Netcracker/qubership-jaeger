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

## Validate

- generate request under active span;
- verify non-empty trace IDs in logs;
- match same trace ID in tracing backend.
