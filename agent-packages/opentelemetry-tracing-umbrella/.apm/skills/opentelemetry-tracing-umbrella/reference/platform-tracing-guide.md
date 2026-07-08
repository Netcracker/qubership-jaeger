# Platform tracing contract (shared)

Binding rules for Qubership/NC services migrating to OpenTelemetry. Every skill
layer must enforce these rules or record an explicit `gap`.

## Mandatory contract

### Client libraries

- Preferred client library per language: the official **OpenTelemetry SDK**
  (Java, Go, Python, C++, and any other language OTel supports).
- Wrappers over the OTel SDK are allowed **only** when every other
  rule in this contract still holds.
- A non-OTel SDK is acceptable only when no OTel SDK exists for the language
  — and still must satisfy the rest of this contract.

### Environment parameters

- `TRACING_ENABLED` — tracing on/off for the workload.
- `TRACING_HOST` — OTLP proxy host (default `nc-diagnostic-agent` in the same
  namespace). Alternative in some clusters: `open-telemetry-collector`.
- Sampler env precedence (first match wins):
  `TRACING_SAMPLER_RATELIMITING` → `TRACING_SAMPLER_PROBABILISTIC` →
  `TRACING_SAMPLER_CONST`.

Contracted values and in-service defaults:

| Parameter                       | Type    | Allowed values   | Default in service    |
|---------------------------------|---------|------------------|-----------------------|
| `TRACING_ENABLED`               | boolean | `true` / `false` | `false` (tracing off) |
| `TRACING_HOST`                  | string  | valid host       | `nc-diagnostic-agent` |
| `TRACING_SAMPLER_RATELIMITING`  | integer | `>= 0`           | `10` (10 per second)  |
| `TRACING_SAMPLER_PROBABILISTIC` | float   | `0.01`–`1.0`     | `0.01` (1%)           |
| `TRACING_SAMPLER_CONST`         | integer | `0` or `1`       | `1` (100%)            |

Use `TRACING_SAMPLER_RATELIMITING` when the stack supports a rate-limiting sampler; fall back to 
`TRACING_SAMPLER_PROBABILISTIC`, then to `TRACING_SAMPLER_CONST`, in that order.

### Export

- OTLP exporter format: `http/protobuf` only.
- Canonical endpoint: `http://${TRACING_HOST}:4318/v1/traces`.
- Default `TRACING_HOST`: `nc-diagnostic-agent` (OTel proxy in the same namespace).
- Alternative proxy in some clusters: `open-telemetry-collector`.
- The proxy exists so services never hard-code direct Jaeger links (Jaeger is
  usually deployed in another namespace); it exposes tracing-protocol endpoints
  and forwards to Jaeger.
- Production path: service → proxy/collector → Jaeger. **Direct-to-Jaeger** is
  fallback/dev only — not the platform contract for migrated services.
- Do not keep Jaeger client, OpenTracing, or legacy Zipkin exporters as the
  active export path.

### Propagation

- Standard: `b3multi` when B3 peer compatibility is required.
- B3 propagators are not part of the core SDK in most languages — add the
  language's B3 propagator module when `b3` / `b3multi` is configured
  (Java: `opentelemetry-extension-trace-propagators`; Go:
  `go.opentelemetry.io/contrib/propagators/b3`).

### Sampling

- OTel sampler: `parentbased_traceidratio` (or equivalent platform wiring).
- Semantics: always continue traces when the incoming request already carries
  sampled trace headers; apply the configured ratio to new root traces.
- Wire the ratio to `TRACING_SAMPLER_PROBABILISTIC` (per the sampler env
  precedence above).
- Never `always_on` as the production default.

### Service naming

- `service.name=${service_name}-${namespace_name}` (resolved at runtime).
- Rationale: unlike Monitoring or Logging, Jaeger carries no namespace/pod
  meta-information, so without the namespace suffix identical services deployed
  in several namespaces are indistinguishable in the trace backend.
- The value must be **resolved** at runtime — a literal unexpanded placeholder
  (e.g. `${NAMESPACE:unknown}` surviving into the exported resource) is a
  contract violation.
- How `service.name` is set is framework-specific — see the language package
  config recipes; the composed `${name}-${namespace}` shape is the same
  everywhere.

#### Namespace sources (inside a Kubernetes pod)

Discover and record the namespace source in discovery evidence. Two supported
ways:

1. **Environment variable injection** — Kubernetes Downward API
   (`fieldRef: metadata.namespace`), a deployer-provided `NAMESPACE` value, or
   Helm built-ins (`.Release.Namespace`).
2. **Mounted service-account file** — read
   `/var/run/secrets/kubernetes.io/serviceaccount/namespace` (mounted
   automatically with the pod's ServiceAccount).

### Endpoint filtering

Exclude probes, metrics, and management endpoints from trace export (health,
actuator, OpenAPI, metrics paths — per framework).

General rules for what to trace:

- endpoint participates in a request chain (receives and/or fans out calls) —
  **must** be traced;
- endpoint runs heavy logic inside the service — **must** be traced;
- endpoint is not part of the public API and is never called by other services
  — should **not** be traced;
- endpoint belongs to a service/debug API (probes, metrics, management) —
  should **not** be traced.

Always-excluded endpoint types: container probes (`/liveness`, `/livez`,
`/readiness`, `/healthz`), metrics endpoints (`/metrics`, `/prometheus`), and
framework management endpoints (`/actuator/*`, `/q/*`).

### Log correlation

- Mandatory `traceId` and `spanId` in application logs (pattern or MDC).
- Expected log shape:
  `[yyyy-MM-ddTHH:mm:ss.SSS] ... [traceId=<value>] [spanId=<value>] ...`
- Existing logging integrations may already satisfy this — confirm in real log
  output before adding another correlation layer.
- Log correlation and span export are independent checks: backend spans do not
  prove IDs in logs, and vice versa.

### Retired libraries

Remove and do not re-introduce as active export paths:

- Jaeger Java client
- OpenTracing API/implementations used as the primary tracer
- Spring Cloud Sleuth, Brave/Zipkin as the sole tracing stack (migrate to OTel)

Language packages may add framework-specific wiring, but **cannot override**
these rules.

## Operational constraints

| Situation                             | Required skill behavior                                                                    |
|---------------------------------------|--------------------------------------------------------------------------------------------|
| Exporter unavailable / collector down | Runtime cannot be `pass`; record buffering/drop risk; set `manual` or `fail` with evidence |
| SDK overhead                          | Do not hard-assert fixed CPU/memory numbers; note overhead is workload-dependent           |
| Third-party SDK regressions           | Recommend verifying SDK version and known issue trackers when symptoms match               |
| Framework/logging wrappers            | Allowed only if log contract above still holds; confirm output before stacking layers      |

Collector/exporter unavailability semantics (SDK defaults): spans buffer
in memory in the batch processor queue (default `maxQueueSize` 2048); when the
queue is full new spans are **dropped**, never persisted to disk; memory and GC
pressure can grow while the endpoint is down. All limits are configurable —
record buffering/drop risk instead of asserting data loss cannot happen.

## Runtime validation

Before declaring runtime `pass`:

- Confirm target collector/proxy alias and endpoint match this contract.
- Traces must reach the platform backend through the documented export path.

## Agent vs user visibility

- Evaluate compliance in `discovery-result.platformContract` (L1 facts) and
  `capability-result.platformContract` (L2 verdicts) — required JSON, internal.
- In user chat briefs, describe gaps in **plain language** with file paths — do
  not expose facet keys or `PASS`/`FAILED` tokens.

## Skill coverage map

| Contract area           | Where enforced                                                   |
|-------------------------|------------------------------------------------------------------|
| Detection / L1 evidence | Language `reference/detection-rules.md`, `models/1-discovery.md` |
| L2 verdicts             | Umbrella `models/2-capability.md`                                |
| L3 maturity             | Umbrella `models/3-maturity.md`                                  |
| L4 migration            | Umbrella `models/4-transformation.md` + language `recipes/`      |
| L5 validation           | Umbrella `models/5-validation.md` + language runtime recipes     |
| Build/registry blockers | Language `reference/build-preconditions.md`                      |
