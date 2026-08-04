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

The migration carries the configured wire format across and never switches it on
its own (common
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Propagation). `OTEL_PROPAGATORS` and programmatic `set_global_textmap` are both
**runtime** in Python, and the programmatic call wins when both are present
([`../models/1-discovery.md`](../models/1-discovery.md) §1.2) — plan the
propagator on one surface.

### Name the class, not just the format

A plan row that says `b3multi` and ships `B3SingleFormat` is wrong on the wire
while every end-to-end test passes; the deprecated alias `B3Format` is the
**multi** one (`../reference/detection-rules.md` §Code signatures). Verify the
class against the b3 version in the service's manifest: guide §Verify constructor
defaults.

```python
# B3 multi-header (X-B3-TraceId / X-B3-SpanId) — required for b3multi
from opentelemetry.propagate import set_global_textmap
from opentelemetry.propagators.b3 import B3MultiFormat

set_global_textmap(B3MultiFormat())
```

### Composite membership and order

Which end of a composite wins on extract, and why inject order is irrelevant:
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Propagation. Derive membership and the winning end from the user's intent
("B3 wins") — never ask which end wins, and never copy an order from another
service's config.

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
app object is created per worker when the app factory runs per worker (i.e. not
under `--preload`), so that path is fork-safe. Under `--preload` it is not — the
app and its tracing setup run in the master; initialize per worker as above.

## Short-lived processes (CLI / one-shot job / worker / `python -c`)

The mirror image of the fork-server case. A `BatchSpanProcessor` exports on a
background thread on an interval; a process that finishes its work and exits
(a CLI command, a one-shot Job, a `python -c` invocation, a notebook kernel)
can terminate **before** that thread flushes, silently dropping the spans it
just created. The `pure-python` target — worker / CLI / library / consumer — hits
this routinely.

Flush on exit. Either register a shutdown hook once at setup:

```python
import atexit
atexit.register(provider.shutdown)   # drains BatchSpanProcessor on interpreter exit
```

or call `provider.force_flush()` explicitly at the end of the unit of work
(before the process returns). For a very short process a `SimpleSpanProcessor`
(synchronous export, nothing to flush) is also acceptable. Without one of these,
end-to-end validation fails intermittently — the trace is created but never
arrives at the backend.

## Legacy config mappings

| From                      | To                                         | 1:1     |
|---------------------------|--------------------------------------------|---------|
| `JAEGER_AGENT_HOST` (udp) | `TRACING_HOST` + OTLP endpoint composition | no      |
| `tracing.enabled`         | `TRACING_ENABLED`                          | yes     |
| `JAEGER_SAMPLER_PARAM`    | `TRACING_SAMPLER_PROBABILISTIC` path       | partial |
| hardcoded Zipkin URL      | OTLP endpoint from `TRACING_HOST`          | no      |

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

Emit **one** endpoint variable, in its own form: the signal-specific
`OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` carries the full URL including `/v1/traces`
(above), while the generic `OTEL_EXPORTER_OTLP_ENDPOINT` is a base URL the
exporter appends to. Writing the path on the generic one yields a double
`/v1/traces` and silent export failure.
