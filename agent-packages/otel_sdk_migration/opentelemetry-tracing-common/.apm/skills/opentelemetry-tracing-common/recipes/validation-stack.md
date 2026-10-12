# Recipe — runtime validation stack (shared)

A parameterized, throwaway stack for the Layer 5 **runtime** tier, used only after the user opts in. Tiers and gating
rules: [`../models/5-validation.md`](../models/5-validation.md).

Use this baseline when the selected environment has **no** tracing backend yet. Confirm image tags from upstream
release notes; read service-specific values from the repository — never hardcode them.

Language packages add build commands, framework env exceptions, and their own "no spans" diagnosis list in
`recipes/validation-stack.md`.

## Preconditions

- the service install path is known —
  [`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md);
- opt-in, environment, and build provenance are settled —
  [`../models/5-validation.md`](../models/5-validation.md) §5.3 Prerequisites. Never validate runtime on a stale image.

## Minimal topology

```text
SUT -> OTLP http/protobuf :4318 -> TRACING_HOST alias -> collector/query backend
```

| Role                  | Dev-minimal choice                                                                  |
|-----------------------|-------------------------------------------------------------------------------------|
| Trace generator       | Target service built from the post-L4 artifact in this session                      |
| Receiver + storage    | Backend with OTLP HTTP ingest and a trace query API (for example Jaeger all-in-one) |
| Platform-shaped alias | Runtime route/service named by `TRACING_HOST` (default `nc-diagnostic-agent`)       |
| Application deps      | Prerequisites from install docs (DB, secrets, volumes)                              |

Wire the SUT with platform env; Layer 4 config maps the rest. The `1.0` sampler is **for L5 smoke only**, never a
production default:

```text
TRACING_ENABLED=true
TRACING_HOST=nc-diagnostic-agent
TRACING_SAMPLER_PROBABILISTIC=1.0
```

## Minimal install (environment-agnostic)

1. Provision a temporary tracing backend that accepts OTLP HTTP.
2. Expose it through the runtime alias used by `TRACING_HOST` — **check first whether that name already exists** in the
   target namespace. If it does, do not overwrite it: another workload resolves it, and repointing it would silently
   divert other services' traces into this throwaway backend. Use a session-scoped alias and point the SUT at that name.
3. Deploy the SUT with the session-unique post-L4 image tag, never `:latest`. When the image was loaded into a local
   runtime store rather than pushed, set `imagePullPolicy: IfNotPresent` (or `Never`), or the cluster tries to pull the
   session tag and fails with `ImagePullBackOff`.
4. Generate traffic to a **non-suppressed business endpoint** — not probes, metrics, or health-only paths
   ([`../models/5-validation.md`](../models/5-validation.md) §5.3).
5. Query traces from the backend API and verify the assertions. Record the install and traffic path in
   `validationPlan.runtime.scenario`, and each checked statement in `validationPlan.runtime.assertions`.
6. Tear down the runtime resources — §Teardown, which runs whatever the verdict is.

## Runtime order

The gates and their order: [`../models/5-validation.md`](../models/5-validation.md) §5.3 — executed here through
[`stand-health-gate.md`](stand-health-gate.md) and [`log-error-triage.md`](log-error-triage.md). Two things about the
assertions themselves are specific to running the stand.

The **entry span** is the server span for an HTTP or framework service. For a worker, consumer, or CLI it is the span
on the unit of work, carrying the producer's context as parent or link. A worker has no server span — asserting one
there fails a correct migration.

A parent-based sampler honors the incoming decision even at ratio `1.0`. If the traffic arrives through a gateway or
mesh that already decided `sampled=0`, the SUT records nothing and the stand looks broken while the configuration is
correct. Check the sampling flag on the inbound headers before chasing an export bug.

## No spans in the backend — check in order

When the stand is healthy and business traffic runs but no service spans appear:

1. **Exporter package and encoding** — the contract is OTLP `http/protobuf`. An exporter that ships JSON or gRPC to a
   protobuf endpoint fails silently.
2. **Endpoint shape** — a traces-specific endpoint variable is used as-is and must include `/v1/traces`; a generic OTLP
   endpoint variable gets `/v1/traces` appended, so a double path silently fails export.
3. **Suppressed endpoint** — the traffic hit a probe, metrics, or excluded path rather than a business endpoint.
4. **Collector reachability** — `TRACING_HOST` resolves, `:4318` is reachable from the pod, `TRACING_ENABLED=true`, and
   the sampler ratio is not `0`.
5. **Dependencies missing from the image** — the runtime stage was built without the OTel packages that L4 added.

Language packages list their own failure modes ahead of these; check those first.

## Teardown

Teardown has two halves with different triggers.

**Runtime resources** come down **whatever the verdict is** — a failed run must not leave a live tracing backend
behind. Remove only what this session created, in reverse order:

1. the SUT deployment, if it was deployed only for validation (keep it when the user asked to retain the stand for
   repeat runs);
2. the `TRACING_HOST` alias — **only** if this session created it. An alias that already existed belongs to the
   environment;
3. the throwaway tracing backend and its storage;
4. any temporary namespace created for the run.

List what was removed in chat, and anything deliberately kept in plan `gaps`.

**Repository files** created for L5 are cleaned only on `pass` —
[`validation-cleanup.md`](validation-cleanup.md) covers throwaway manifests, scripts, and local Dockerfiles, not
cluster resources.
