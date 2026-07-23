# Recipe — dependency migration (Python)

Concrete moves for Layer 4 §4.1 (`dependencyMigration`) — see common
[`models/4-transformation.md`](../../opentelemetry-tracing-common/models/4-transformation.md)
§4.1.

Read versions from the target manifest (`requirements.txt`, `pyproject.toml`,
`poetry.lock`, `Pipfile`); do not hardcode versions here.

**Prerequisite:** complete Python [`models/4-transformation.md`](../models/4-transformation.md)
Step 0 (framework stack) before emitting §4.1 rows — dependency moves follow
`discovery-result.service.framework`, not a free choice.

## Framework stack → dependency path

| `service.framework`   | §4.1 focus                                                                          |
|-----------------------|--------------------------------------------------------------------------------------|
| `fastapi`             | baseline + `opentelemetry-instrumentation-fastapi` (ASGI)                            |
| `django`              | baseline + `opentelemetry-instrumentation-django` (WSGI/ASGI)                        |
| `flask`               | baseline + `opentelemetry-instrumentation-flask` (WSGI)                              |
| `pure-python`         | OTel SDK baseline modules only                                                       |
| `unknown`             | conservative baseline; record assumptions in `gaps`                                 |

Framework and instrumentation signatures:
[`../reference/detection-rules.md`](../reference/detection-rules.md).

## Source-of-truth constraints

From the common platform contract
([`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)):

- preferred client library: OpenTelemetry SDK for Python;
- framework instrumentation is allowed only if it preserves platform requirements;
- Jaeger/OpenTracing/py_zipkin client libraries are retired migration targets;
- OTLP is the recommended export format.

## Legacy → OTel moves

Applies to every framework stack when these are the active tracing dependencies:

- remove: `opentracing`, `opentracing-instrumentation`, `jaeger-client`,
  `py_zipkin`/`python-zipkin`, framework shims (`flask-opentracing`,
  `django-opentracing`), and the retired `opentelemetry-exporter-jaeger*`
  (when they form the active stack).
- add: `opentelemetry-api`, `opentelemetry-sdk`, the OTLP HTTP exporter, and the
  B3 propagator module (baseline below), plus the framework instrumentation
  package from the table above.

## Target baseline modules

Required for `pure-python`, and as the SDK foundation for every framework path:

- `opentelemetry-api`
- `opentelemetry-sdk`
- `opentelemetry-exporter-otlp-proto-http`
- `opentelemetry-propagator-b3`

Use `opentelemetry-exporter-otlp-proto-grpc` only when the environment explicitly
requires gRPC OTLP.

Zero-code auto-instrumentation (optional, chosen at Step 0b — **not** alongside
manual `.instrument()` calls):

- `opentelemetry-distro`
- `opentelemetry-instrumentation` (provides the `opentelemetry-instrument` and
  `opentelemetry-bootstrap` commands)

`opentelemetry-bootstrap -a install` adds the instrumentation packages that match
the libraries already installed — useful for reproducing the auto path, but pin
the resulting set in the manifest rather than running it at container start.

## Manifest guardrails

- Keep the tracing packages in the **runtime** dependency set, not `dev`/`test`
  extras — they must be present in the built image.
- OTel packages version-lock together; mixing an old `opentelemetry-api` with a
  newer SDK/exporter raises `ImportError` on moved symbols. Install them as one
  coherent set and let the resolver align them; record the resolved set in the
  migration plan. If the service pins an old `opentelemetry-api` for an unrelated
  reason, upgrade the whole OTel set together rather than partially — record an
  unresolvable conflict in `gaps`, never leave a split version set.
