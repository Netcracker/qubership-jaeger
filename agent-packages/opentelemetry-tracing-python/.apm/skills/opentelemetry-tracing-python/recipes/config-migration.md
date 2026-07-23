# Recipe — configuration migration (Python)

Concrete mappings for Layer 4 §4.2 (`configMigration`).

## Source of truth

Contracted parameters, export format, propagation, sampling, and service
naming come from the common platform contract
([`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md))
— do not restate or override them here.

### Service name and namespace (Python pitfall)

Build `service.name` from **resolved** values only. Reading a raw env template
(`os.environ.get("OTEL_SERVICE_NAME", "${NAMESPACE}")`) or a Helm placeholder
that was never expanded ships a literal `${NAMESPACE}` into the resource
attributes. Read the namespace from an injected env var (`NAMESPACE` /
`MICROSERVICE_NAMESPACE` via Downward API or deployer), or from the mounted
serviceaccount file `/var/run/secrets/kubernetes.io/serviceaccount/namespace`,
and compose `${name}-${namespace}` at startup. Verify the resolved value — never
ship a literal `${...}`.

Set it via `OTEL_SERVICE_NAME` / `OTEL_RESOURCE_ATTRIBUTES=service.name=...` or a
programmatic `Resource.create({"service.name": ...})`.

## Propagation

**The migration preserves the wire format; it does not change it.** Carry the
configured inject format across, raise a conflict with the contract as a
**question** to the user, and on a greenfield service ask the user to pick
`B3` / `B3_MULTI` / `W3C` / a multi-format set instead of choosing silently
(common
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Propagation).

`OTEL_PROPAGATORS` and programmatic `set_global_textmap` are both **runtime** in
Python — the format stays switchable without a rebuild. If **both** are present,
the programmatic `set_global_textmap` wins — it overwrites the global propagator
after SDK autoconfigure reads `OTEL_PROPAGATORS`. Treat the programmatic call as
the source of truth and record the env value as overridden.

### Name the class, not just the format

`B3SingleFormat` (env value `b3`) injects the **single** `b3` header;
`B3MultiFormat` (env value `b3multi`) injects `X-B3-TraceId` / `X-B3-SpanId` /
`X-B3-Sampled`. The legacy name `B3Format` is a **deprecated alias of
`B3MultiFormat`** — it emits `X-B3-*`, not single `b3`. Source coordinates and
the exact header constants:
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Verify constructor defaults — verify against the b3 version in the service's
manifest.

A plan row that says "b3multi" and ships `B3SingleFormat` is wrong on the wire
while every end-to-end test still passes.

```python
# B3 multi-header (X-B3-TraceId / X-B3-SpanId) — required for b3multi
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.b3 import B3MultiFormat

set_global_textmap(B3MultiFormat())
```

### Composite: extract order matters, inject writes everything

On **extract**, `CompositePropagator` chains the context through every member in
order, so the **last** member that finds a context overwrites the earlier result
— priority goes to the **last** entry. That is the opposite of Spring Boot.
Derive the order yourself from the user's intent ("B3 wins") — do not ask which
end wins, and do not copy a list from a Java service.

On **inject** the composite loops every member, so both formats below are written
to each outgoing request (a later member overrides the same carrier key). Order
does not change which formats are emitted.

```python
# extract: accepts traceparent and X-B3-*; B3 wins when both arrive (it is last)
# inject:  writes traceparent AND X-B3-* on every outgoing request
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.composite import CompositePropagator
from opentelemetry.trace.propagation.tracecontext import TraceContextTextMapPropagator
from opentelemetry.propagators.b3 import B3MultiFormat

set_global_textmap(CompositePropagator([
    TraceContextTextMapPropagator(),
    B3MultiFormat(),
]))
```

Multi-format is a valid target and needs nothing extra around it — the
assumption is that adjacent tooling does not overwrite an existing context.

## Fork-server initialization (gunicorn / uvicorn)

A `BatchSpanProcessor` started at **module import** under `--preload` lives in the
master process; its background export thread does not survive `fork()`, so
workers export nothing. Initialize the SDK **per worker**:

```python
# gunicorn.conf.py
def post_fork(server, worker):
    from myapp.tracing import setup_tracing  # builds provider + BatchSpanProcessor
    setup_tracing()
```

For framework instrumentors called at app startup (`instrument_app(app)`), the
app object is created per worker, so that path is already fork-safe.

## Legacy config mappings

| From                       | To                                            | 1:1     |
|----------------------------|-----------------------------------------------|---------|
| `JAEGER_AGENT_HOST` (udp)  | `TRACING_HOST` + OTLP endpoint composition    | no      |
| `tracing.enabled`          | `TRACING_ENABLED`                             | yes     |
| `JAEGER_SAMPLER_PARAM`     | `TRACING_SAMPLER_PROBABILISTIC` path          | partial |
| hardcoded Zipkin URL       | OTLP endpoint from `TRACING_HOST`             | no      |

## Required target env shape

```text
TRACING_ENABLED=true|false
TRACING_HOST=nc-diagnostic-agent
TRACING_SAMPLER_PROBABILISTIC=0.01
OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=http://${TRACING_HOST}:4318/v1/traces
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_PROPAGATORS=b3multi
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=${TRACING_SAMPLER_PROBABILISTIC}
OTEL_SERVICE_NAME=${MICROSERVICE_NAME}-${NAMESPACE}
```

`OTEL_PROPAGATORS=b3multi` above is the **contract default**, used only when the
service has no format configured and the user chose it. An existing format is
preserved instead — see §Propagation.

The Python OTLP HTTP exporter treats the two endpoint variables differently. The
signal-specific `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` is used **as-is** — give it
the full traces URL including `/v1/traces` (the form above). The generic
`OTEL_EXPORTER_OTLP_ENDPOINT` is a **base** URL — the exporter appends
`/v1/traces` itself, so it must **not** already contain the path. Pick one form —
putting `/v1/traces` on the generic variable produces a double `/v1/traces` path
and silent export failure.
