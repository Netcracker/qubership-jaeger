# Recipe — runtime validation stack (Go)

A parameterized, throwaway stack for the Layer 5 **runtime** tier, used only
after the user opts in. Shared runtime gates and tiers:
Go [`models/5-validation.md`](../models/5-validation.md) and umbrella
[`models/5-validation.md`](../../opentelemetry-tracing-umbrella/models/5-validation.md).

Use this baseline when the selected environment has **no** tracing backend yet.
Confirm image tags from upstream release notes; read service-specific values from
the repository — never hardcode them.

## Preconditions

- service install path is known (see
  [`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md));
- user opts in to runtime validation and names a deploy environment with sufficient permissions;
- **Agent rule:** after Layer 4 edits, run
  [`fresh-build-and-image.md`](fresh-build-and-image.md) before any runtime deploy —
  do not validate runtime on a stale image.

## Minimal topology

```text
SUT -> OTLP http/protobuf :4318 -> TRACING_HOST alias -> collector/query backend
```

| Role                  | Dev-minimal choice                                                            |
|-----------------------|-------------------------------------------------------------------------------|
| Trace generator       | Target service built from the post-L4 artifact in this session                |
| Receiver + storage    | Backend with OTLP HTTP ingest and trace query API (e.g. Jaeger all-in-one)    |
| Platform-shaped alias | Runtime route/service named by `TRACING_HOST` (default `nc-diagnostic-agent`) |
| Application deps      | Prerequisites from install docs (DB, secrets, volumes)                        |

Wire the SUT with platform env (Layer 4 config maps the rest). Use `1.0` sampler
**for L5 smoke only** — not production defaults:

```text
TRACING_ENABLED=true
TRACING_HOST=nc-diagnostic-agent
TRACING_SAMPLER_PROBABILISTIC=1.0
```

### Minimal install (environment-agnostic)

1. Provision a temporary tracing backend that accepts OTLP HTTP.
2. Expose it through the runtime alias used by `TRACING_HOST`.
3. Deploy the SUT with the post-L4 image and required dependencies.
4. Generate traffic to a **non-suppressed business endpoint** (not probes,
   metrics, or health-only paths — see umbrella
   [`models/5-validation.md`](../../opentelemetry-tracing-umbrella/models/5-validation.md)
   §5.3).
5. Query traces from the backend API and verify assertions.
6. Tear down or revert temporary runtime resources after validation (see cleanup below).

## Runtime order

**Runtime pass requires all gates in order:**

1. [`stand-health-gate.md`](../../opentelemetry-tracing-umbrella/recipes/stand-health-gate.md) — Ready workload, stable restarts, non-empty endpoints
2. [`log-error-triage.md`](../../opentelemetry-tracing-umbrella/recipes/log-error-triage.md) — classified log errors; no `blocks-e2e`
3. Business traffic — non-suppressed endpoint through the normal service path
4. Tracing assertions — resolved `service.name`, server span, propagation, log correlation

Assert propagation on the **wire headers** (a receiver dumping incoming headers
shows `b3` vs `X-B3-*` vs `traceparent`), and on span hierarchy where a mesh is
in the path. A single `trace_id` across services passes with the wrong inject
format too, because receivers extract leniently — see umbrella
[`5-validation.md`](../../opentelemetry-tracing-umbrella/models/5-validation.md) §5.3.
This matters most in Go, where `b3.New()` without options emits single `b3`
while the plan may say `b3multi`.

**Not sufficient for pass:** Jaeger spans from probe traffic alone while the SUT
is `CrashLoopBackOff`, not Ready, or restart-prone.

After runtime **`pass`**, run
[`validation-cleanup.md`](../../opentelemetry-tracing-umbrella/recipes/validation-cleanup.md).
