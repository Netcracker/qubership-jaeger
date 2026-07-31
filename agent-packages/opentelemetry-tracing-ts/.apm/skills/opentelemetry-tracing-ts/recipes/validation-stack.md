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
2. Expose it through the runtime alias used by `TRACING_HOST` — **check first
   whether that name already exists** in the target namespace. If it does, do not
   overwrite it: another workload resolves it, and repointing it would silently
   divert other services' traces into this throwaway backend. Use a session-scoped
   alias instead and set `TRACING_HOST` on the SUT to that name.
3. Deploy the SUT with the post-L4 image and required dependencies — the
   session-unique tag from
   [`fresh-build-and-image.md`](fresh-build-and-image.md), never `:latest`. When the
   image was loaded into a local runtime store rather than pushed, set
   `imagePullPolicy: IfNotPresent` (or `Never`), or the cluster tries to pull the
   session tag and fails with `ImagePullBackOff`.
4. Generate traffic to a **non-suppressed business endpoint** (not probes,
   metrics, or health-only paths — see common
   [`models/5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md)
   §5.3).
5. Query traces from the backend API and verify assertions. Record the install and
   traffic path in `validationPlan.runtime.scenario` and each checked statement in
   `validationPlan.runtime.assertions`.
6. Tear down the runtime resources — see §Teardown below, which runs whatever the
   verdict is.

## Runtime order

**Runtime pass requires all gates in order:**

1. [`stand-health-gate.md`](../../opentelemetry-tracing-common/recipes/stand-health-gate.md) — Ready workload, stable restarts, non-empty endpoints
2. [`log-error-triage.md`](../../opentelemetry-tracing-common/recipes/log-error-triage.md) — classified log errors; no `blocks-e2e`
3. Business traffic — non-suppressed endpoint through the normal service path
4. Tracing assertions — resolved `service.name`, **entry span**, propagation, log
   correlation. The entry span is the server span for an HTTP or framework service;
   for a `pure-node` worker or consumer it is the consumer span carrying the
   producer's context as parent or link. A worker has no server span — asserting one
   there fails a correct migration

Assert propagation on the **wire headers** (a receiver dumping incoming headers
shows `b3` vs `X-B3-*` vs `traceparent`), and on span hierarchy where a mesh is in
the path. A single `trace_id` across services passes with the wrong inject format
too, because receivers extract leniently — see common
[`5-validation.md`](../../opentelemetry-tracing-common/models/5-validation.md) §5.3.
This matters in Node, where a bare `new B3Propagator()` emits single `b3` while the
plan may say `b3multi`.

The entry span appearing at all also confirms the Node-specific load-order/bundler
fix worked — an ESM hoist or a bundler that ate the monkey-patch shows up here as
**no** entry span despite a clean build.

A parent-based sampler still honors the incoming decision even at ratio `1.0`: if
the traffic arrives through a gateway or mesh that already decided `sampled=0`, the
SUT records nothing and the stand looks broken while the configuration is correct.
Check the sampling flag on the inbound headers before chasing an export bug.

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
   the loader hook is present alongside `--import` — `register()` from
   `node:module` on Node 20.6+, or the older
   `--experimental-loader=@opentelemetry/instrumentation/hook.mjs` flag
   ([`../models/4-transformation.md`](../models/4-transformation.md) §ESM loader
   hook). Without it, monkey-patch instrumentation cannot wrap an ESM `import`
   even when load order is correct, and this looks identical to a load-order bug
   (clean build, empty trace). Verify the actual entrypoint
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
5. **Pruned dependencies.** A runtime stage built with `npm ci --omit=dev`,
   `npm prune --production`, or `NODE_ENV=production` drops OTel packages that L4
   put in `devDependencies` — the image ships without them and the symptom is
   identical to a load-order bug. Check the installed set inside the image
   ([`fresh-build-and-image.md`](fresh-build-and-image.md)).
6. **Duplicate `@opentelemetry/api`.** Two copies in `node_modules` split the
   global tracer/propagator registry, so instrumentation and app code write to
   different globals. `npm ls @opentelemetry/api` must show one resolved version
   ([`dependency-migration.md`](dependency-migration.md)).
7. **Suppressed endpoint.** Traffic hit a probe/metrics/excluded path, not a
   business endpoint.
8. **Collector reachability.** `TRACING_HOST` service resolves and `:4318` is
   reachable from the pod; `TRACING_ENABLED=true` and sampler ratio is not `0`.

## Teardown

Runs **whatever the verdict is** — a failed run must not leave a live tracing
backend behind. Remove only what this session created, in reverse order:

1. the SUT deployment, if it was deployed only for validation (keep it when the
   user asked to retain the stand for repeat runs);
2. the `TRACING_HOST` alias — **only** if this session created it. An alias that
   already existed belongs to the environment;
3. the throwaway tracing backend and its storage;
4. any temporary namespace created for the run.

List what was removed in chat, and anything deliberately kept in plan `gaps`.

Separately, after runtime **`pass`**, run
[`validation-cleanup.md`](../../opentelemetry-tracing-common/recipes/validation-cleanup.md)
— that recipe covers **repository files** created for L5 (throwaway manifests,
scripts, local Dockerfiles), not cluster resources.
