# Layer 4 — Transformation (Python)

Shared plan structure, algorithm, and section numbering (§4.1–§4.5):
[`opentelemetry-tracing-common/models/4-transformation.md`](../../opentelemetry-tracing-common/models/4-transformation.md).

Run the **Python gate below before §4.1**. Then fill §4.1–§4.4 from recipes:

| Section                      | Recipe                                                                                                                                        |
|------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| §4.1 `dependencyMigration`   | [`../recipes/dependency-migration.md`](../recipes/dependency-migration.md)                                                                    |
| §4.2 `configMigration`       | [`../recipes/config-migration.md`](../recipes/config-migration.md) + [`../recipes/logging-correlation.md`](../recipes/logging-correlation.md) |
| §4.3 `codeMigration`         | [`../recipes/code-migration.md`](../recipes/code-migration.md)                                                                                |
| §4.4 `asyncContextMigration` | [`../recipes/async-context-migration.md`](../recipes/async-context-migration.md)                                                              |

## Step 0 — Framework stack decision (mandatory)

**Framework stack** = how the service serves requests (from L1 →
`service.framework` in `discovery-result.json`): FastAPI (ASGI), Django or Flask
(WSGI), or a non-web worker/library — not "one repository = one stack" by
default.

Read `discovery-result.service.framework` and pick exactly one migration path.
Do not emit §4.1 or §4.2 rows before this is fixed.

The instrumentor per stack, and the best-effort mapping for `unknown`, are
[`../reference/framework-coverage.md`](../reference/framework-coverage.md). What
this gate adds is the **config surface** the plan must target:

| `service.framework` | Config surface                  |
|---------------------|---------------------------------|
| `fastapi`           | env + programmatic/instrumentor |
| `django`            | env + `settings.py`             |
| `flask`             | env + app-factory instrument    |
| `pure-python`       | env + programmatic setup        |
| `unknown`           | env; record the assumption in `gaps` |

Pull versions from the repository manifest (`requirements.txt`/`pyproject.toml`); never
pin in the plan.

## Step 0b — Instrumentation-mechanism guardrails (mandatory)

After the framework stack is chosen, validate the **mechanism**. Pick **one** and
reject the forbidden combinations in the plan:

- **End with one active tracing stack.** Remove Zipkin/py_zipkin/OpenTracing/Jaeger
  client as active tracing stacks.
- **ASGI vs WSGI must match the server model.** FastAPI/Starlette are ASGI — use
  the ASGI/FastAPI instrumentation. Flask is WSGI — use the WSGI/Flask
  instrumentation. Django's instrumentor hooks the request handler and works under
  **both** WSGI and ASGI, so do not hard-pin it to WSGI. A generic WSGI middleware
  on an ASGI app (or the reverse) does not instrument requests.
- **Name the mechanism explicitly — Python has three.** `launcher` (the zero-code
  `opentelemetry-instrument` command with `opentelemetry-distro`, auto-instruments
  every detected library at startup), `instrumentor` (explicit programmatic
  `FastAPIInstrumentor.instrument_app()` / `DjangoInstrumentor().instrument()`
  calls), and `hand-spans` (spans written by hand with `start_as_current_span`).
  The plan states which one it targets.
- **`pure-python` → mechanism is `hand-spans`.** With no web framework there is
  nothing for the `launcher`/`instrumentor` axis to hook, so the XOR below is
  N/A; instrument the units of work by hand with `start_as_current_span`. The
  guardrails that still apply are one active stack, platform contract, and (for
  a short-lived process) flush on exit — see
  [`../recipes/config-migration.md`](../recipes/config-migration.md) §Short-lived
  processes.
- **`launcher` XOR `instrumentor` for the same library.** Do **not** run the
  launcher *and* call `.instrument()` for the same library — running both may
  double-instrument and duplicate spans (notably `instrument_app()` on top of the
  launcher; many instrumentors otherwise no-op the second call). Choose `launcher`
  **or** `instrumentor`.
- **Messaging/library instrumentors are a separate axis.** Adding
  `opentelemetry-instrumentation-celery` / `-kafka-python` / `-confluent-kafka` for
  context propagation across a broker is **not** the `launcher`-vs-`instrumentor`
  XOR and does not by itself make the service `mixed` — evaluate it independently.
- **Preserve the platform contract** (`TRACING_*`, OTLP, propagation, sampling)
  regardless of mechanism.

Fork-server pitfall (record as a risk in the plan, verify at runtime): under
gunicorn/uvicorn with pre-forked workers, where the SDK is initialized decides
whether the workers export at all —
[`../recipes/config-migration.md`](../recipes/config-migration.md)
§Fork-server initialization.

Check the plan carries every field in common
[`models/4-transformation.md`](../../opentelemetry-tracing-common/models/4-transformation.md) §Plan sections.
