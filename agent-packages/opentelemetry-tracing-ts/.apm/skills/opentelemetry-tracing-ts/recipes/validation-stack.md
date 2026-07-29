# Recipe — runtime validation stack (TypeScript / Node)

A parameterized, throwaway stack for the Layer 5 **runtime** tier, used only after
the user opts in. Shared runtime gates and tiers:
TypeScript [`models/5-validation.md`](../models/5-validation.md) and common
[`models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md).

Use this baseline when the selected environment has **no** tracing backend yet.
Confirm image tags from upstream release notes; read service-specific values from
the repository — never hardcode them.

## Preconditions

- service install/build path is known (see
  [`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md));
- user opts in to runtime validation and names a deploy environment with sufficient permissions;
- **Agent rule:** after Layer 4 edits, run
  [`fresh-build-and-image.md`](fresh-build-and-image.md) before any runtime deploy —
  do not validate runtime on a stale image.

## Minimal topology

```text
SUT -> OTLP http/protobuf :4318 -> TRACING_HOST alias -> collector/query backend
```

| Role | Dev-minimal choice |
| ----------------------- | ------------------------------------------------------------------------------- |
| Trace generator | Target service built from the post-L4 image in this session |
| Receiver + storage | Backend with OTLP HTTP ingest and trace query API (e.g. Jaeger all-in-one) |
| Platform-shaped alias | Runtime route/service named by `TRACING_HOST` (default `nc-diagnostic-agent`) |
| Application deps | Prerequisites from install docs (DB, secrets, volumes) |

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
   metrics, or health-only paths — see common
   [`models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md)
   §5.3).
5. Query traces from the backend API and verify assertions.
6. Tear down or revert temporary runtime resources after validation (see cleanup below).

## Runtime order

**Runtime pass requires all gates in order:**

1. [`stand-health-gate.md`](../../opentelemetry-tracing-common/recipes/stand-health-gate.md) — Ready workload, stable restarts, non-empty endpoints
2. [`log-error-triage.md`](../../opentelemetry-tracing-common/recipes/log-error-triage.md) — classified log errors; no `blocks-e2e`
3. Business traffic — non-suppressed endpoint through the normal service path
4. Tracing assertions — resolved `service.name`, server span, propagation, log correlation

Assert propagation on the **wire headers** (a receiver dumping incoming headers
shows `b3` vs `X-B3-*` vs `traceparent`), and on span hierarchy where a mesh is in
the path. A single `trace_id` across services passes with the wrong inject format
too, because receivers extract leniently — see common
[`5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md) §5.3.
This matters in Node, where a bare `new B3Propagator()` emits single `b3` while the
plan may say `b3multi`.

A server span appearing at all also confirms the Node-specific load-order/bundler
fix worked — an ESM hoist or a bundler that ate the monkey-patch shows up here as
**no** server span despite a clean build.

**Not sufficient for pass:** Jaeger spans from probe traffic alone while the SUT is
`CrashLoopBackOff`, not Ready, or restart-prone.

## No spans in Jaeger — check in order (Node)

When the stand is healthy and business traffic runs but no service spans appear,
diagnose in this order — the first four are Node-specific and account for most
"clean build, empty trace" cases:

1. **Load order.** The tracing bootstrap must init before instrumented modules.
   ESM top-level `import './tracing.js'` is hoisted and runs too late — use
   `--import` (or CJS `-r`). On ESM with the `launcher`/auto-instrumentation
   mechanism, also confirm
   `--experimental-loader=@opentelemetry/instrumentation/hook.mjs` is present
   alongside `--import` — without it, monkey-patch instrumentation cannot wrap
   an ESM `import` even when load order is correct, and this looks identical to
   a load-order bug (clean build, empty trace). Verify the actual entrypoint
   (`scripts.start` / Dockerfile `CMD` / `NODE_OPTIONS`).
2. **Bundler.** If the artifact is bundled (esbuild/webpack/tsup/ncc), monkey-patch
   auto-instrumentation has nothing to wrap — externalize instrumented deps or use
   hand-spans.
3. **Exporter package/encoding.** `exporter-trace-otlp-http` sends JSON; if the
   collector expects protobuf, spans never land — use `exporter-trace-otlp-proto`
   for the contract `http/protobuf`.
4. **Endpoint shape.** `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` used as-is (must include
   `/v1/traces`); generic `OTEL_EXPORTER_OTLP_ENDPOINT` gets `/v1/traces` appended
   — a double path silently fails export.
5. **Suppressed endpoint.** Traffic hit a probe/metrics/excluded path, not a
   business endpoint.
6. **Collector reachability.** `TRACING_HOST` service resolves and `:4318` is
   reachable from the pod; `TRACING_ENABLED=true` and sampler ratio is not `0`.

After runtime **`pass`**, run
[`validation-cleanup.md`](../../opentelemetry-tracing-common/recipes/validation-cleanup.md).
