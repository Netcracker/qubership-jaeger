# Framework coverage (Python)

This list is the source of truth for which Python frameworks are first-class in
this package; the `service.framework` enum in
[`../schemas/L1-discovery-result.schema.json`](../schemas/L1-discovery-result.schema.json)
is this list plus `unknown`, and the two are extended together. Coverage is
extensible, not a hard gate: detection is signature-based, and a framework that is
not classified confidently falls back to `framework=unknown` plus the conservative
SDK path.

When a best-effort framework **is** identified confidently, prefer its matching
OTel contrib instrumentor over the bare SDK and record the framework and the
choice in the plan `gaps`, so a reviewer sees what was assumed.

First-class framework stacks:

- `fastapi` (ASGI app; `opentelemetry-instrumentation-fastapi`)
- `django` (WSGI/ASGI app; `opentelemetry-instrumentation-django`)
- `flask` (WSGI app; `opentelemetry-instrumentation-flask`)
- `pure-python` (worker/library/consumer with manual OTel SDK wiring)

Best-effort framework stacks. These are **not** enum values: detect them
generically, keep `framework=unknown`, and plan the instrumentor named here:

- Starlette → `opentelemetry-instrumentation-asgi`
- aiohttp → `opentelemetry-instrumentation-aiohttp-server` (client: `-aiohttp-client`)
- Tornado → `opentelemetry-instrumentation-tornado`
- Falcon → `opentelemetry-instrumentation-falcon`
- Sanic → generic `opentelemetry-instrumentation-asgi`
- Bottle → `opentelemetry-instrumentation-bottle`
- gRPC services → `opentelemetry-instrumentation-grpc`
