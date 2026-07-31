# Framework coverage (Go)

First-class framework stacks for this package:

- `cloudcore-fiber` (Fiber HTTP stack with org/platform server wrapper + actuator tracing)
- `net-http` (stdlib HTTP server/client)
- `pure-go` (library/service with manual OTEL SDK wiring)

Best-effort framework stacks:

- `gin`
- `echo`
- other router/middleware stacks with explicit OTel middleware.

If framework stack cannot be detected with confidence, emit `framework=unknown` and
continue with conservative SDK migration path plus `gaps` note.
