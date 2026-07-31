# Framework coverage (Python)

This list is the **single source of truth** for which Python frameworks are
first-class in this package; the `service.framework` schema enum mirrors it.
Treat it as extensible coverage, not a hard gate — detection is generic
(signature-based), and anything not confidently classified falls back to
`unknown` + the conservative SDK path. Extend the first-class set here (and the
schema enum) when a repository shows a framework is common in practice.

First-class framework stacks for this package:

- `fastapi` (ASGI app; `opentelemetry-instrumentation-fastapi`)
- `django` (WSGI/ASGI app; `opentelemetry-instrumentation-django`)
- `flask` (WSGI app; `opentelemetry-instrumentation-flask`)
- `pure-python` (worker/library/consumer with manual OTel SDK wiring)

Best-effort framework stacks (detect generically; emit `framework=unknown` unless
a confident match is possible). When a best-effort framework **is** confidently
identified, prefer its matching OTel contrib instrumentor over the bare SDK:

- Starlette → `opentelemetry-instrumentation-asgi`
- aiohttp → `opentelemetry-instrumentation-aiohttp-server` (client: `-aiohttp-client`)
- Tornado → `opentelemetry-instrumentation-tornado`
- Falcon → `opentelemetry-instrumentation-falcon`
- Sanic → generic `opentelemetry-instrumentation-asgi`
- Bottle → `opentelemetry-instrumentation-bottle`
- gRPC services → `opentelemetry-instrumentation-grpc`

Only when no matching instrumentor exists, or the framework cannot be identified
with confidence, fall back to `framework=unknown` and the conservative SDK
migration path plus a `gaps` note.
