# Recipe — runtime validation stack

A parameterized, throwaway stack for the Layer 5 **runtime** tier, used only
after the user opts in and answers the environment questionnaire in
[`../models/5-validation.md`](../models/5-validation.md). Everything here is a
template: confirm image tags against their upstream release pages and read
service-specific values from the repository, never hardcode them.

## Dev-minimal profile (skill checks)

Use this baseline only when the selected environment has **no** tracing backend
yet. Preconditions:

- service install path is known (see
  [`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md));
- user opts in to runtime validation;
- the user specifies a deploy environment with sufficient permissions.

**Agent rule:** after Layer 4 edits, run
[`fresh-build-and-image.md`](fresh-build-and-image.md) before any runtime deploy.
Do not validate runtime on a stale image.

Logical topology:

```text
<SUT> --OTLP http/protobuf :4318--> <TRACING_HOST alias> --> <collector/query backend>
```

| Role | Dev-minimal choice |
| --- | --- |
| Trace generator | The target service built from the post-L4 artifact in this session |
| Receiver + storage | Any backend exposing OTLP HTTP ingest and trace query API |
| Platform-shaped alias | Runtime alias named by `TRACING_HOST` (default `nc-diagnostic-agent`) |
| Application deps | Service prerequisites from install docs (DB, secrets, volumes) |

Wire the SUT with platform env (Layer 4 config maps the rest):

```text
TRACING_ENABLED=true
TRACING_HOST=nc-diagnostic-agent
TRACING_SAMPLER_PROBABILISTIC=1.0
```

### Minimal install (environment-agnostic)

1. Provision a temporary tracing backend that accepts OTLP HTTP.
2. Expose it through the runtime alias used by `TRACING_HOST`.
3. Deploy the SUT with a post-L4 image and required dependencies.
4. Generate traffic to a non-suppressed business endpoint.
5. Query traces from the backend API and verify assertions.
6. Tear down temporary runtime resources after validation.

**Runtime pass requires all gates in order** (see
[`../models/5-validation.md`](../models/5-validation.md)):

1. [`../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/stand-health-gate.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/stand-health-gate.md) — Ready pod, stable restarts, non-empty endpoints
2. [`../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/log-error-triage.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/log-error-triage.md) — classified log errors
3. Tracing assertions — `service.name`, server span, propagation, log correlation

**Not sufficient for pass:** Jaeger service list or spans from probe traffic alone
while the SUT pod is `CrashLoopBackOff`, not Ready, or restart-prone.

## Components

| Role | What | Notes |
| --- | --- | --- |
| Tracing backend | Jaeger all-in-one or OTel collector with OTLP HTTP and query API | use a published version from upstream release notes |
| Proxy alias | Runtime route/service named by `TRACING_HOST` | keeps service config platform-shaped |
| Service deps | Whatever the target needs to start | derive from repository docs/config |
| Service image | Built per [Layer 4](../models/4-transformation.md) | use install docs or user-provided artifact |

## Wiring the service to the backend

Point the service at the proxy service name on the OTLP HTTP port, matching the
platform contract:

```text
TRACING_ENABLED=true
TRACING_HOST=<proxy-service-name>          # default nc-diagnostic-agent
TRACING_SAMPLER_PROBABILISTIC=1.0          # 100% for the test only
```

For **Quarkus** services on a pre-built image, also set explicit runtime env
(see [`../reference/quarkus-platform-contract.md`](../reference/quarkus-platform-contract.md)):

```text
QUARKUS_OTEL_SDK_DISABLED=false
QUARKUS_OTEL_EXPORTER_OTLP_ENDPOINT=http://<proxy-service-name>:4318
```

Nested `${tracing.sdk.disabled.${TRACING_ENABLED}}` toggles copied from Spring
often leave the SDK off when only `TRACING_ENABLED=true` is set.

The framework config produced in Layer 4 turns platform env into OTLP endpoint,
`b3multi` propagation, and `parentbased_traceidratio` sampling. For Spring Boot
and Pure Java, do not redeclare `otel.*` on top of a correctly built image.
For Quarkus runtime validation, the two `QUARKUS_OTEL_*` env vars above are the
exception when toggling export on a single shared image.

## Bring-up order and readiness

1. Backend + proxy alias first; confirm the query API answers.
2. Service dependencies (DB migrated, secrets present) before the app.
3. The app last. Size the probes to the **real** start time — JVM services
   commonly need minutes, not seconds, to pass readiness; an aggressive
   `livenessProbe` kills the pod mid-startup and masks the real result. Prefer a
   `startupProbe`, or generous `initialDelaySeconds`, over tight liveness.
4. **Immediately after apply:** run [`../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/stand-health-gate.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/stand-health-gate.md)
   — do not query Jaeger until the gate passes (see §Exercise and assert).

## Exercise and assert

**Step 1 — stand health (mandatory):** execute
[`../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/stand-health-gate.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/stand-health-gate.md). Post the **L5 Stand health** brief.

**Step 2 — log triage (mandatory):** execute
[`../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/log-error-triage.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/log-error-triage.md). Post the **L5 Log errors** brief.

**Step 3 — traffic and tracing:** generate traffic against a **non-suppressed**
business endpoint (see endpoint selection in
[`../models/5-validation.md`](../models/5-validation.md)), then query the backend
and assert tracing fields.

Tracing assertions apply **only after** steps 1–2 pass:

- a span with the resolved `service.name=<name>-<namespace>`;
- `span.kind=server` for the exercised path;
- propagation intact (`traceparent` or `b3`/`b3multi`); one `trace_id` across any
  async hop;
- non-empty `traceId`/`spanId` in the service logs for the request.

### Post-deploy verification checklist

Before claiming success, verify **in order**:

1. [`../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/stand-health-gate.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/stand-health-gate.md) — rollout OK, Ready `1/1`, stable
   restarts, endpoints populated, ≥60s observation window
2. [`../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/log-error-triage.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/log-error-triage.md) — no `blocks-e2e` findings
3. Tracing assertions — server span, propagation, log correlation

If readiness fails, endpoints are empty, or restarts increase after Ready,
**stop** and fix the stand. Tracing-only smoke (Jaeger spans while pod
crash-loops) **does not** count as end-to-end pass.

## Teardown

After runtime **`pass`**, run [`../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/validation-cleanup.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/recipes/validation-cleanup.md)
— remove ephemeral L5-only files; do not delete L4 service changes.

For disposable stands (namespace/compose), tear down runtime resources when
cleanup is done so repeated runs start clean.
