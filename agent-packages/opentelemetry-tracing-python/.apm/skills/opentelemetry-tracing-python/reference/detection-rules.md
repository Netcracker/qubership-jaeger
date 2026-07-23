# Detection rules (Python)

Layer 1 signature catalogue for Python services. Detection is **generic and
signature-based** — match imports/symbols/keys, and classify to a first-class
framework only on confident evidence; otherwise `unknown`.

## Dependency signatures (manifests)

Distribution names as they appear in `requirements.txt` / `pyproject.toml` /
`poetry.lock` / `Pipfile`.

| Distribution                                        | Bucket | Technology            |
|-----------------------------------------------------|--------|-----------------------|
| `opentracing`, `opentracing-instrumentation`        | legacy | opentracing           |
| `jaeger-client`                                      | legacy | jaeger-client         |
| `py_zipkin`, `python-zipkin`                          | legacy | zipkin                |
| `flask-opentracing`, `django-opentracing`            | legacy | opentracing           |
| `opentelemetry-exporter-jaeger*` (retired)           | legacy | jaeger-client         |
| `opentelemetry-api`                                  | modern | otel-api              |
| `opentelemetry-sdk`                                  | modern | otel-sdk              |
| `opentelemetry-exporter-otlp-proto-http`             | modern | otel-exporter         |
| `opentelemetry-exporter-otlp-proto-grpc`             | modern | otel-exporter         |
| `opentelemetry-propagator-b3`                        | modern | otel-propagator       |
| `opentelemetry-instrumentation-*`                    | modern | otel-instrumentation  |
| `opentelemetry-distro`, `opentelemetry-instrumentation` | modern | otel-distro        |

Aggregate flags:

- `hasOtelApi`: OTel API package present.
- `hasOtelSdk`: OTel SDK package present.
- `hasExporter`: OTLP/Zipkin/Jaeger exporter package present.
- `hasLegacy`: legacy tracer stack wired (not just transitive).

## Framework signatures

| Framework | Signature                                                                     |
|-----------|-------------------------------------------------------------------------------|
| `fastapi` | `from fastapi import FastAPI`; ASGI `app`; uvicorn or gunicorn uvicorn worker |
| `django`  | `manage.py`, `DJANGO_SETTINGS_MODULE`, `wsgi.py`/`asgi.py`, `INSTALLED_APPS`  |
| `flask`   | `from flask import Flask`; WSGI `app`; gunicorn/uwsgi                         |
| `pure-python` | OTel wiring with no web framework import (worker/CLI/consumer)             |

Best-effort: Starlette, aiohttp, Tornado, Falcon, Sanic, Bottle, gRPC — when
confidently identified, prefer the matching contrib instrumentor; otherwise emit
`unknown` + note. Mapping: [`framework-coverage.md`](framework-coverage.md).

## Configuration signatures

Platform-level keys (from the umbrella platform contract):

- `TRACING_ENABLED`
- `TRACING_HOST` (default `nc-diagnostic-agent`)
- `TRACING_SAMPLER_RATELIMITING`
- `TRACING_SAMPLER_PROBABILISTIC`
- `TRACING_SAMPLER_CONST`

OTel keys:

- `OTEL_EXPORTER_OTLP_ENDPOINT`
- `OTEL_EXPORTER_OTLP_PROTOCOL` (`http/protobuf` expected)
- `OTEL_PROPAGATORS` (contract default `b3multi`; runtime scope — drives inject
  and extract; an already-configured format is preserved, not replaced)
- `OTEL_TRACES_SAMPLER`
- `OTEL_TRACES_SAMPLER_ARG`
- `OTEL_SERVICE_NAME` / `OTEL_RESOURCE_ATTRIBUTES`
- `OTEL_PYTHON_LOG_CORRELATION`

Legacy/framework keys:

- `JAEGER_AGENT_HOST`, `JAEGER_AGENT_PORT`, `JAEGER_SAMPLER_PARAM`
- Django `settings.py` tracing blocks; `OPENTRACING_TRACER`

## Code signatures

OTel:

- `trace.get_tracer(...)` / `trace.set_tracer_provider(...)`
- `tracer.start_as_current_span(...)` / `tracer.start_span(...)`
- `trace.get_current_span(...)`
- `set_global_textmap(...)` / `CompositePropagator(...)` — composite priority is
  the **last** entry on extract
- `B3MultiFormat` (X-B3-*) vs `B3SingleFormat` (single `b3`); `B3Format` is a
  deprecated alias of `B3MultiFormat` (multi)
- `OTLPSpanExporter` from `opentelemetry.exporter.otlp.proto.http.trace_exporter`
- `FastAPIInstrumentor` / `DjangoInstrumentor` / `FlaskInstrumentor`

Legacy:

- `opentracing.tracer` / `opentracing.set_global_tracer` / `init_tracer`
- `jaeger_client.Config`
- `py_zipkin` symbols

## Instrumentation mode signatures

| Evidence                                                    | Mode   |
|-------------------------------------------------------------|--------|
| `opentelemetry-instrument` launcher / distro, no app spans  | auto   |
| `Instrumentor().instrument()` calls, no app spans           | auto   |
| Explicit `start_as_current_span` in app code                | manual |
| Both auto path and explicit spans                           | mixed  |
| No symbols from table                                       | none   |

`mode` is the coarse **detected** state. For the **target** mechanism the
transformation gate distinguishes `launcher` (the `opentelemetry-instrument`
command) from `instrumentor` (programmatic `.instrument()` calls) — both surface
here as `auto`. See [`../models/4-transformation.md`](../models/4-transformation.md) Step 0b.

## Async-boundary signatures

| Symbol/pattern                                               | Boundary type                   |
|-------------------------------------------------------------|---------------------------------|
| `ThreadPoolExecutor`, `run_in_executor`, `threading.Thread` | thread-pool / asyncio-executor  |
| `@shared_task`, `@app.task`, `.delay()`, `.apply_async()`   | celery-task                     |
| `kafka-python` / `confluent-kafka` / `aiokafka` produce/consume | kafka-producer / kafka-consumer |
| `multiprocessing`, `subprocess`                             | subprocess                      |
| outbound HTTP client in async worker                        | http-client                     |

`async`/`await` and `asyncio.create_task` propagate `contextvars` automatically —
mark those `contextWrapper: true`, not a loss candidate. Mark a boundary as a
context-loss candidate when no explicit context propagation is visible
(`context.attach`, OTel Celery/Kafka instrumentation, or manual inject/extract).

## Platform-contract signatures

Map to mandatory checks:

- `service.name=${name}-${namespace}` or equivalent runtime construction;
- namespace source via Downward API, Helm `.Release.Namespace`, or serviceaccount file;
- OTLP endpoint `http://${TRACING_HOST}:4318/v1/traces` (or equivalent host+path composition);
- propagation `b3multi` (or explicitly documented compatible format);
- sampler uses parent-based ratio behavior in production (`parentbased_traceidratio`);
- probe/metrics endpoint exclusions (`/health*`, `/metrics`, `/prometheus`, `/livez`, `/readyz`);
- log format includes `traceId` and `spanId`.
