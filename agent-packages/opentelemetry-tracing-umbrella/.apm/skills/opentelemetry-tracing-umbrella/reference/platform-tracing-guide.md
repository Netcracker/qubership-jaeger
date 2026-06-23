# Platform tracing contract (shared)

Binding rules for Qubership/NC services migrating to OpenTelemetry. Every skill
layer must enforce these rules or record an explicit `gap`.

## Mandatory contract

### Environment parameters

- `TRACING_ENABLED` — tracing on/off for the workload.
- `TRACING_HOST` — OTLP proxy host (default `nc-diagnostic-agent` in the same
  namespace). Alternative in some clusters: `open-telemetry-collector`.
- Sampler env precedence (first match wins):
  `TRACING_SAMPLER_RATELIMITING` → `TRACING_SAMPLER_PROBABILISTIC` →
  `TRACING_SAMPLER_CONST`.

### Export

- OTLP exporter format: `http/protobuf` only.
- Canonical endpoint: `http://${TRACING_HOST}:4318/v1/traces`.
- Default `TRACING_HOST`: `nc-diagnostic-agent` (OTel proxy in the same namespace).
- Alternative proxy in some clusters: `open-telemetry-collector`.
- Production path: service → proxy/collector → Jaeger. **Direct-to-Jaeger** is
  fallback/dev only — not the platform contract for migrated services.
- Do not keep Jaeger client, OpenTracing, or legacy Zipkin exporters as the
  active export path.

### Propagation

- Standard: `b3multi` when B3 peer compatibility is required.
- Add `opentelemetry-extension-trace-propagators` when `b3` / `b3multi` is
  configured.

### Sampling

- OTel sampler: `parentbased_traceidratio` (or equivalent platform wiring).
- Never `always_on` as the production default.

### Service naming

- `service.name=${service_name}-${namespace_name}` (resolved at runtime).
- Discover namespace from deployment/runtime metadata (Downward API, Helm,
  AppDeployer, service-account file, or equivalent) and record the source in
  discovery evidence.

### Endpoint filtering

Exclude probes, metrics, and management endpoints from trace export (health,
actuator, OpenAPI, metrics paths — per framework).

### Log correlation

- Mandatory `traceId` and `spanId` in application logs (pattern or MDC).
- Allowed wrappers (Micrometer bridge, CloudCore logging) only if this contract
  still holds.

### Retired libraries

Remove and do not re-introduce as active export paths:

- Jaeger Java client
- OpenTracing API/implementations used as the primary tracer
- Spring Cloud Sleuth, Brave/Zipkin as the sole tracing stack (migrate to OTel)

Language packages may add framework-specific wiring, but **cannot override**
these rules.

## Operational constraints

| Situation | Required skill behavior |
| --- | --- |
| Exporter unavailable / collector down | Runtime cannot be `pass`; record buffering/drop risk; set `manual` or `fail` with evidence |
| SDK overhead | Do not hard-assert fixed CPU/memory numbers; note overhead is workload-dependent |
| Third-party SDK regressions | Recommend verifying SDK version and known issue trackers when symptoms match |
| Wrappers (Micrometer, CloudCore) | Allowed only if mandatory contract above still holds |

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

| Contract area | Where enforced |
| --- | --- |
| Detection / L1 evidence | Language `reference/detection-rules.md`, `models/1-discovery.md` |
| L2 verdicts | Umbrella `models/2-capability.md` |
| L3 maturity | Umbrella `models/3-maturity.md` |
| L4 migration | Umbrella `models/4-transformation.md` + language `recipes/` |
| L5 validation | Umbrella `models/5-validation.md` + language runtime recipes |
| Build/registry blockers | Language `reference/build-preconditions.md` |
