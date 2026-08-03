# Framework coverage (Go)

This list is the **single source of truth** for which Go stacks are first-class in this package. Detection is
signature-based, so treat the list as extensible coverage rather than a hard gate: anything not confidently classified
falls back to `unknown` plus the conservative SDK path.

First-class framework stacks, matching the `service.framework` schema enum:

- `cloudcore-fiber` — Fiber HTTP stack with the org/platform server wrapper and actuator tracing;
- `net-http` — stdlib HTTP server and client;
- `gin` — router middleware plus SDK and OTLP exporter;
- `echo` — router middleware plus SDK and OTLP exporter;
- `pure-go` — library, worker, or service with manual OTel SDK wiring.

Best-effort stacks — any other router or middleware stack with explicit OTel middleware. Detect generically and emit
`framework=unknown`, then name the identified router and the chosen middleware in the plan `gaps` so a reviewer can see
what was assumed.

Prefer a matching contrib middleware over the bare SDK whenever one is confidently identified. Fall back to
`framework=unknown` with the conservative SDK path only when no middleware exists or the stack cannot be identified
with confidence.
