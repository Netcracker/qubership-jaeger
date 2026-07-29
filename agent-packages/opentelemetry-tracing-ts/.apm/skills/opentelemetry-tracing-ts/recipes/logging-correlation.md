# Recipe — trace IDs in logs (TypeScript / Node)

Adding `traceId`/`spanId` to logs is mandatory.

Expected shape:

```text
... [traceId=<value>] [spanId=<value>] ...
```

## Rule

1. First check whether the project's logging setup already emits these fields.
2. If not, wire the current span context into log records.
3. Keep field names stable in the output: `traceId`, `spanId`.

## Read the active span (dependency-free helper)

`spanContext()` returns `traceId`/`spanId` already as hex strings — no formatting
needed (unlike Python):

```ts
import { trace } from '@opentelemetry/api';

function traceFields(): { traceId: string; spanId: string } {
  const ctx = trace.getActiveSpan()?.spanContext();
  return ctx && ctx.traceId
    ? { traceId: ctx.traceId, spanId: ctx.spanId }
    : { traceId: '', spanId: '' };
}
```

## pino (recommended default via mixin)

A `mixin` runs for **every** log line and stamps the contract fields directly, so
no record is missing them and the field names match the contract:

```ts
import pino from 'pino';
import { trace } from '@opentelemetry/api';

const logger = pino({
  mixin() {
    const ctx = trace.getActiveSpan()?.spanContext();
    return ctx?.traceId ? { traceId: ctx.traceId, spanId: ctx.spanId } : {};
  },
});
```

## winston (format that stamps contract fields)

```ts
import { createLogger, format, transports } from 'winston';
import { trace } from '@opentelemetry/api';

const traceFormat = format((info) => {
  const ctx = trace.getActiveSpan()?.spanContext();
  info.traceId = ctx?.traceId ?? '';
  info.spanId = ctx?.spanId ?? '';
  return info;
});

const logger = createLogger({
  format: format.combine(traceFormat(), format.json()),
  transports: [new transports.Console()],
});
```

## Alternative — OTel logging instrumentation (with a hard caveat)

`@opentelemetry/instrumentation-pino` / `-winston` / `-bunyan` auto-inject
`trace_id`, `span_id`, and `trace_flags` into log records. The injected field
**names are `trace_id` / `span_id`** (snake_case); the contract wants `traceId` /
`spanId`, so you must map them:

```ts
// with instrumentation-pino active, rename in a formatter/serializer
formatters: {
  log(obj) {
    if (obj.trace_id) { obj.traceId = obj.trace_id; obj.spanId = obj.span_id; }
    return obj;
  },
}
```

> **Caveat.** The instrumentation only stamps records created **while a span is
> active** and only after `registerInstrumentations` ran and patched the logger
> instance. Records outside a span, or from a logger created before instrumentation
> loaded, have no trace fields — a downstream consumer that keys on `traceId` sees
> gaps. The mixin/format approach above does not have this failure mode because it
> sets the fields on *every* record. If you use the instrumentation, verify the
> logger is created after the bootstrap and map the field names.

Registering a `TracerProvider` does **not** wire log correlation by itself: spans
reaching the backend prove export, not correlation. Always verify the fields in
actual log output as a separate check.

## Validate

- generate request under active span;
- verify non-empty trace IDs in logs;
- match same trace ID in tracing backend.
