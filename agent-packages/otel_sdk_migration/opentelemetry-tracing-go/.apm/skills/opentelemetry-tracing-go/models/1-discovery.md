# Layer 1 — Discovery (Go)

**Goal:** enumerate every existing element of tracing implementation.
Discovery reports what exists, not whether it works.

- **Input:** repository root (Go source, `go.mod`, config, deployment, Helm/k8s).
- **Output:** `discovery-result.json` validated by
  [`../schemas/L1-discovery-result.schema.json`](../schemas/L1-discovery-result.schema.json).
- **Detection signatures:** [`../reference/detection-rules.md`](../reference/detection-rules.md).

Run sections **1.0–1.6**; emit every required JSON object. Missing evidence →
`unknown` or empty arrays per schema; record why in `gaps` — do not omit sections.

## 1.0 Framework discovery

Set `service.framework` (schema enum) and optional `service.name`:

| Framework         | Typical evidence                                                                                 |
|-------------------|--------------------------------------------------------------------------------------------------|
| `cloudcore-fiber` | Fiber HTTP stack with org/platform server wrapper + `WithTracer(...)` (see `detection-rules.md`) |
| `net-http`        | stdlib `net/http` server, no Fiber/Gin/Echo router                                               |
| `gin`             | `gin-gonic/gin`                                                                                  |
| `echo`            | `labstack/echo`                                                                                  |
| `pure-go`         | OTel wired without the frameworks above                                                          |
| `unknown`         | insufficient evidence — note in `gaps`                                                           |

## 1.1 Dependency discovery

Inputs:

- `go.mod`, `go.sum`, `vendor/`, workspace files;
- optional `go list -m all` or equivalent dependency graph command.

Classify every tracing artifact into a bucket and set the aggregate flags
(`hasOtelApi`, `hasOtelSdk`, `hasExporter`, `hasLegacy`) — module catalogue and
bucket assignments:
[`../reference/detection-rules.md`](../reference/detection-rules.md) §Dependency
signatures.

## 1.2 Configuration discovery

Inspect config/env locations:

- `.env`, Helm values/templates, Deployment env vars;
- app config loaders (`koanf`, `viper`, env/yaml/struct-based project loaders);
- hardcoded tracing constants in Go files.

Collect:

- export endpoint/protocol/target guess;
- propagation **inject** and **extract** sets (separately — see below) and
  per-component wiring (HTTP/Kafka/async);
- sampler type and ratio.

### Propagation: two sets, resolved from the actual constructor

Record `propagation.inject` and `propagation.extract` separately, in the order
written — do not normalize it against another stack's convention. Why the two
directions differ and which end of a Go composite wins on extract:
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Propagation. Both sources are `runtime` scope in Go: `OTEL_PROPAGATORS` and
programmatic `otel.SetTextMapPropagator(...)`.

Read the propagator **options**, not the constructor name — a bare `b3.New()`
injects the single `b3` header, not `X-B3-*`
(`detection-rules.md` §Code signatures). Verify it against the b3 version in
`go.mod`, not against a version cited elsewhere: guide §Verify constructor
defaults.

## 1.3 API discovery (AST/symbol)

Scan Go sources for the OTel, legacy, and platform-wrapper symbols catalogued in
[`../reference/detection-rules.md`](../reference/detection-rules.md) §Code
signatures. Record `family`, `symbol`, `file`, `line` for each hit.

## 1.4 Instrumentation discovery

Classify `instrumentation.mode` (`auto` / `manual` / `mixed` / `none`) from
`detection-rules.md` §Instrumentation mode signatures.

## 1.5 Async-boundary discovery

Record each context-loss candidate with its boundary type, and set
`contextWrapper` true only when context is explicitly propagated. Boundary
catalogue: [`../reference/detection-rules.md`](../reference/detection-rules.md)
§Async-boundary signatures.

## 1.6 Platform-contract discovery

Resolve every facet of `platformContract` from the Go signals:
[`../reference/detection-rules.md`](../reference/detection-rules.md)
§Platform-contract signatures. For missing inspectable evidence, use `unknown`
and record `gaps`.

## User-facing brief (mandatory)

Post the **L1 Discovery brief** — content and rules in common
[`reference/user-briefs.md`](../../opentelemetry-tracing-common/reference/user-briefs.md), language additions in
[`../SKILL.md`](../SKILL.md) §3.1. Do not proceed to L2 until it is posted.
