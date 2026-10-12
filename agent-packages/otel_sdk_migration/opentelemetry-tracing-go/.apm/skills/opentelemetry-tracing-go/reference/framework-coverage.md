# Framework coverage (Go)

This list is the source of truth for which Go stacks are first-class in this package; the `service.framework` enum in
[`../schemas/L1-discovery-result.schema.json`](../schemas/L1-discovery-result.schema.json) is this list plus `unknown`,
and the two are extended together. Coverage is extensible, not a hard gate: detection is signature-based, and a stack
that is not classified confidently falls back to `framework=unknown` plus the conservative SDK path.

When a best-effort stack **is** identified confidently, prefer its matching contrib middleware over the bare SDK and
record the router and the choice in the plan `gaps`, so a reviewer sees what was assumed.

First-class framework stacks:

- `cloudcore-fiber` — Fiber HTTP stack with the org/platform server wrapper and actuator tracing;
- `net-http` — stdlib HTTP server and client;
- `gin` — router middleware plus SDK and OTLP exporter;
- `echo` — router middleware plus SDK and OTLP exporter;
- `pure-go` — library, worker, or service with manual OTel SDK wiring.

Best-effort stacks — any other router or middleware stack with explicit OTel middleware. Detect generically and keep
`framework=unknown`.
