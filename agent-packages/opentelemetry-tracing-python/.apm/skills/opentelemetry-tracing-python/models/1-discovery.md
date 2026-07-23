# Layer 1 — Discovery (Python)

**Goal:** enumerate every existing element of tracing implementation.
Discovery reports what exists, not whether it works.

- **Input:** repository root (Python source, dependency manifests, config, deployment, Helm/k8s).
- **Output:** `discovery-result.json` validated by
  [`../schemas/L1-discovery-result.schema.json`](../schemas/L1-discovery-result.schema.json).
- **Detection signatures:** [`../reference/detection-rules.md`](../reference/detection-rules.md).

Run sections **1.0–1.6**; emit every required JSON object. Missing evidence →
`unknown` or empty arrays per schema; record why in `gaps` — do not omit sections.

## 1.0 Framework discovery

Set `service.framework` (schema enum) and optional `service.name`. Detect from
**generic signatures** (imported web framework, ASGI vs WSGI entrypoint), not from
a fixed whitelist — classify to a first-class value only when the evidence is
confident, otherwise `unknown`. First-class coverage and best-effort fallbacks:
[`../reference/framework-coverage.md`](../reference/framework-coverage.md).

| Framework     | Typical evidence                                                                             |
|---------------|----------------------------------------------------------------------------------------------|
| `fastapi`     | `from fastapi import FastAPI`; ASGI app; uvicorn/gunicorn+uvicorn worker                     |
| `django`      | `manage.py`, `DJANGO_SETTINGS_MODULE`, `wsgi.py`/`asgi.py`, `INSTALLED_APPS`                 |
| `flask`       | `from flask import Flask`; WSGI app; gunicorn/uwsgi entrypoint                               |
| `pure-python` | OTel wired without a web framework above (worker, CLI, library, consumer)                    |
| `unknown`     | insufficient or best-effort evidence (Starlette, aiohttp, Tornado, Falcon…) — note in `gaps` |

## 1.1 Dependency discovery

Inputs:

- `requirements.txt` (and `requirements/*.txt`), `pyproject.toml`, `setup.cfg`,
  `setup.py`, `poetry.lock`, `Pipfile`/`Pipfile.lock`, `uv.lock`;
- optional `pip freeze` / `pip list` or `opentelemetry-bootstrap -a list` output.

Classify tracing artifacts into buckets (catalogue in `detection-rules.md`):

- **legacy**: `opentracing`, `jaeger-client`, `py_zipkin`/`python-zipkin`,
  framework OpenTracing shims (`flask-opentracing`, `django-opentracing`),
  the retired `opentelemetry-exporter-jaeger*`;
- **modern**: `opentelemetry-api`, `opentelemetry-sdk`, OTLP exporters
  (`opentelemetry-exporter-otlp-proto-http` / `-grpc`), B3 propagator
  (`opentelemetry-propagator-b3`), instrumentation packages
  (`opentelemetry-instrumentation-*`), and the auto-instrumentation launcher
  (`opentelemetry-distro`, `opentelemetry-instrumentation`).

Set aggregate flags:

- `hasOtelApi`
- `hasOtelSdk`
- `hasExporter`
- `hasLegacy`

## 1.2 Configuration discovery

Inspect config/env locations:

- `.env`, Helm values/templates, Deployment env vars;
- app settings modules (Django `settings.py`, Pydantic `Settings`, `os.environ`
  reads, `python-dotenv`);
- hardcoded tracing constants and programmatic SDK setup in `.py` files.

Collect:

- export endpoint/protocol/target guess;
- propagation **inject** and **extract** sets (separately — see below) and
  per-component wiring (HTTP/Kafka/async);
- sampler type and ratio.

### Propagation: two sets, resolved from the actual configuration

Record `propagation.inject` and `propagation.extract` separately: the SDK
extracts as a race (several formats tried, **last** wins in Python — the
composite chains the context through every propagator) but injects as a
fan-out — `CompositePropagator.inject` loops every member, so **all** configured
formats are written (a later member overrides the same carrier key). A merged
list hides the case where a service reads B3 and still emits only `traceparent`.
See
[`platform-tracing-guide.md`](../../opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md)
§Propagation.

Sources, both `runtime` scope in Python (interpreted — no build-time propagation
surface):

- `OTEL_PROPAGATORS` env (`b3`, `b3multi`, `tracecontext`, `jaeger`, …);
- programmatic `set_global_textmap(...)` — read the **class**, not just the
  presence of B3. `B3SingleFormat` (and env `b3`) injects the **single** `b3`
  header; `B3MultiFormat` (and env `b3multi`) injects `X-B3-*`. The legacy name
  `B3Format` is a deprecated alias of `B3MultiFormat` — it emits `X-B3-*`, not
  single `b3`. Mechanism and source coordinates:
  [`platform-tracing-guide.md`](../../opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md)
  §Verify constructor defaults — check them against the b3 version in the repo's
  manifest, not the version cited there.

With `CompositePropagator([...])` the **last** entry wins on extract. That is the
opposite of Spring Boot — record the order as written, do not normalize it
against another stack's convention.

If **both** `OTEL_PROPAGATORS` and a programmatic `set_global_textmap(...)` are
present, the programmatic call wins (it overwrites the global after autoconfigure).
Record the programmatic value as the effective one and mark the env value overridden.

## 1.3 API discovery (AST/symbol)

Find symbols:

- OTel: `trace.get_tracer`, `tracer.start_as_current_span`, `start_span`,
  `trace.get_current_span`, `TracerProvider`, `set_tracer_provider`,
  `set_global_textmap`;
- legacy: `opentracing.tracer`/`init_tracer`, `jaeger_client.Config`,
  `py_zipkin` symbols;
- framework instrumentors (`FastAPIInstrumentor`, `DjangoInstrumentor`,
  `FlaskInstrumentor`) — signatures in `detection-rules.md`.

Record `family`, `symbol`, `file`, `line`.

## 1.4 Instrumentation discovery

Classify `instrumentation.mode`:

- `auto`: no explicit spans but zero-code launcher evidence
  (`opentelemetry-instrument` in the entrypoint/Dockerfile CMD,
  `opentelemetry-distro`) or `Instrumentor().instrument()` calls;
- `manual`: explicit span creation in app code;
- `mixed`: both;
- `none`: no evidence.

## 1.5 Async-boundary discovery

Detect context-loss candidates. **Note:** `contextvars` propagate automatically
across `await` and `asyncio.create_task`, so plain `async`/`await` is **not** a
loss boundary — mark those `contextWrapper: true`. The real losses are:

- thread pools / executors (`ThreadPoolExecutor`, `loop.run_in_executor`,
  `threading.Thread`);
- Celery tasks (`@shared_task`, `@app.task`, `.delay()`, `.apply_async()`);
- Kafka producers/consumers (`kafka-python`, `confluent-kafka`, `aiokafka`) and
  other messaging libs in the manifest;
- `multiprocessing` / subprocess handoffs;
- async HTTP clients and callback-style execution.

Mark `contextWrapper` true only when context is explicitly propagated (captured
`context.attach(...)`, OTel Celery/Kafka instrumentation, or manual
inject/extract).

## 1.6 Platform-contract discovery

Collect mandatory contract evidence:

- `TRACING_ENABLED`, `TRACING_HOST`, `TRACING_SAMPLER_*`;
- OTLP `http/protobuf` path and host alias;
- propagation — the injected format (contract default `b3multi`) and the
  extracted set, resolved from the propagator class/env value;
- `parentbased_traceidratio` or equivalent parent-based ratio behavior;
- `service.name=${name}-${namespace}` and namespace source
  (Downward API/Helm/SA file);
- excluded probe/metrics endpoints;
- `traceId`/`spanId` in log output.

For missing inspectable evidence, use `unknown` and record `gaps`.

## User-facing brief (mandatory)

After `discovery-result.json`, post the **L1 Discovery brief** in chat per
[`../SKILL.md`](../SKILL.md) §3.1 (5–10 bullets: framework, dependencies, config,
instrumentation, async boundaries, platform gaps). Do not proceed to L2 until posted.
