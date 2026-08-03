# Recipe — trace IDs in logs (TypeScript / Node)

Adding `traceId`/`spanId` to logs is mandatory.

Expected shape for a text logger:

```text
... [traceId=<value>] [spanId=<value>] ...
```

A structured logger satisfies the same contract with the fields themselves —
`"traceId":"<value>"`, `"spanId":"<value>"` in the JSON record. What the contract
fixes is the **field names**, not the bracket syntax.

Emit as a §4.2 `configMigration` row: `{ from, to, oneToOne, note }`, where `from`
is the current logging setup (or `none`) and `note` records the mechanism chosen
below.

## Rule

1. First check whether the project's logging setup already emits these fields.
2. If not, wire the current span context into log records.
3. Keep field names stable in the output: `traceId`, `spanId`.
4. Pick **one** mechanism — the manual hook below **or** the OTel logging
   instrumentation. Both at once stamps every record twice, under two different
   names.

## Read the active span (dependency-free helper)

`spanContext()` returns `traceId`/`spanId` already as hex strings — no formatting
needed. Guard with `isSpanContextValid`: a truthiness check on `traceId` also
accepts the all-zero invalid context and would log `000…0`.

```ts
import { trace, isSpanContextValid } from '@opentelemetry/api';

function traceFields(): { traceId: string; spanId: string } | Record<string, never> {
  const ctx = trace.getActiveSpan()?.spanContext();
  return ctx && isSpanContextValid(ctx)
    ? { traceId: ctx.traceId, spanId: ctx.spanId }
    : {}; // omit the keys entirely — never emit empty strings
}
```

**Omit, do not blank.** A record written outside any span carries no trace fields
at all. Writing `traceId: ""` instead breaks queries that filter on the field's
presence and pollutes the index with a value that matches nothing.

## pino (recommended default via mixin)

A `mixin` runs for **every** log line and stamps the contract fields directly, so
no record is missing them and the field names match the contract:

```ts
import pino from 'pino';
import { trace, isSpanContextValid } from '@opentelemetry/api';

const logger = pino({
  mixin() {
    const ctx = trace.getActiveSpan()?.spanContext();
    return ctx && isSpanContextValid(ctx) ? { traceId: ctx.traceId, spanId: ctx.spanId } : {};
  },
});
```

## winston (format that stamps contract fields)

```ts
import { createLogger, format, transports } from 'winston';
import { trace, isSpanContextValid } from '@opentelemetry/api';

const traceFormat = format((info) => {
  const ctx = trace.getActiveSpan()?.spanContext();
  if (ctx && isSpanContextValid(ctx)) {
    info.traceId = ctx.traceId;
    info.spanId = ctx.spanId;
  }
  return info; // no span → no keys, same as pino above
});

const logger = createLogger({
  format: format.combine(traceFormat(), format.json()),
  transports: [new transports.Console()],
});
```

## bunyan

Bunyan has no per-record hook comparable to pino's `mixin`. Either use
`@opentelemetry/instrumentation-bunyan` with the rename below, or wrap the emit
path and merge `traceFields()` into the record there. Record whichever was used in
`platformContract.logging.correlationDep`.

## Alternative — OTel logging instrumentation (with a hard caveat)

`@opentelemetry/instrumentation-pino` / `-winston` / `-bunyan` auto-inject
`trace_id`, `span_id`, and `trace_flags` into log records. The injected field
**names are `trace_id` / `span_id`** (snake_case); the contract wants `traceId` /
`spanId`, so map them **and drop the originals** — otherwise every record carries
both spellings:

```ts
// with instrumentation-pino active, rename in a formatter/serializer
formatters: {
  log(obj) {
    if (obj.trace_id) {
      obj.traceId = obj.trace_id;
      obj.spanId = obj.span_id;
      delete obj.trace_id;
      delete obj.span_id;
      delete obj.trace_flags; // keep only if a consumer reads the sampling flag
    }
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

## Correlation is independent of sampling

A span that the sampler dropped still has a valid trace ID, so the log line carries
a `traceId` whose trace **never reaches the backend** — the OTel instrumentation
marks this with `trace_flags: "00"` (sampled traces show `"01"`). This is correct
behavior, not a defect: logs stay correlated with each other regardless of sampling.

It does constrain validation. "Find the same trace ID in the tracing backend" only
holds for a sampled trace — which is why the L5 smoke runs at
`TRACING_SAMPLER_PROBABILISTIC=1.0`. On a production ratio, a missing trace for a
logged ID is expected; check `trace_flags`, or the sampled flag on the wire, before
calling it a broken export.

## Validate

- generate a request under an active span;
- verify the field **names** in real output are `traceId`/`spanId` — not
  `trace_id`/`span_id`, and not both;
- verify the values are non-empty and the keys are absent outside a span;
- match the same trace ID in the tracing backend, for a **sampled** trace.
