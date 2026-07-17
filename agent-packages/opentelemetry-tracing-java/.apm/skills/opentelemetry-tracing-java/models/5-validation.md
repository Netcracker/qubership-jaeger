# Layer 5 — Validation (Java)

Shared tiers, `validationPlan` structure, static/configuration checks, runtime
gating, and pass/fail rules:

[`opentelemetry-tracing-umbrella/models/5-validation.md`](../../opentelemetry-tracing-umbrella/models/5-validation.md).

This file defines Java **execution** details only. Runtime validation is **not**
"build and deploy whatever service we touched" — the target app and install scope
are unknown until discovery runs. Follow
[`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md)
before any runtime or compile work.

Emit and run **static** and **configuration** tiers per umbrella §5.1–§5.2 by
default (repository only). Set `validationPlan.runtime.status` to `manual` with
`manualInstruction` until the steps below complete and the user opts in.

## Installation and test path (before runtime)

Run this **before** the environment questionnaire or any bootstrap commands:

1. **Find installation documentation** — see
   [`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md).
   Cite paths found (`docs/installation/*`, Helm docs, `bootstrap/`, CI workflows).
2. **If docs exist** — derive runtime validation from them (image source, deploy
   commands, test commands). Do not add a second undocumented build pipeline.
3. **If no install doc** — analyze integration-test modules and CI workflows.
   If the path is clear, align runtime checks with that harness; if not, **ask the
   user** how the service is installed and tested.
4. **Registry/build blockers** — if docs or `pom.xml` imply a private Maven
   registry and credentials are missing, record in plan `gaps` per
   [`../reference/build-preconditions.md`](../reference/build-preconditions.md).
   Set `validationPlan.runtime.status` to `manual` — do **not** deploy a cached
   image as a workaround.

## Fresh build gate (once after L4, before runtime deploy)

When Layer 4 edits exist, execute
[`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md)
**once** after L4 — **before** any runtime deploy of the SUT for end-to-end.

Do **not** run Maven during L1–L3. Do **not** run a **second** full rebuild
when starting end-to-end if the post-L4 build already succeeded and L4 is unchanged —
**verify** provenance (runner JAR mtime after last L4 edit, image tag) per the
recipe Step 1b.

1. Purge stale `target/` and cached SUT images in the active runtime image store.
2. `mvn clean package` (or install-doc equivalent) — exit 0, **after L4 only**.
3. Build container image with a session-unique tag and publish/import it using
   the selected runtime environment flow.
4. Post the **L5 Fresh build** brief from the recipe.

**Never** reuse pre-existing local tags or a build that predates L4. If Maven
cannot run, runtime is at most `manual` or `fail` — not `pass`.

Static/configuration L5 tiers do **not** trigger a rebuild — inspect repository files only.
Runtime end-to-end is different: it must use either the fresh post-L4 image from this
session or a previously produced post-L4 image whose provenance still matches
the current L4 edits. If provenance does not match, run the single post-L4 build
again before runtime deploy.

## Environment questionnaire (runtime opt-in only)

After an install/test path is documented or confirmed by the user, and only if
runtime validation is still desired:

1. **Where does the service run?** The user must name a concrete environment
   with deploy permissions — do not invent or silently assume one.
2. **Tracing backend** — existing collector/Jaeger, or **dev-minimal profile** in
   [`../recipes/validation-stack.md`](../recipes/validation-stack.md) (Jaeger
   all-in-one + `nc-diagnostic-agent` alias).
3. **Service dependencies** — from install docs (DB, secrets, volumes), not
   guessed. Reuse the repository's official k8s/Helm manifests where they exist.

If the user cannot answer or declines, keep `runtime.status` as `manual`.

### Post-build prompt (mandatory)

When a migrated artifact **builds successfully** and Layer 4 edits are in place,
ask explicitly whether to run runtime end-to-end on the built image. Wait for the user
to confirm **and** to supply the target environment before applying any manifest
from `validation-stack.md`.

## Runtime scenario (when path is known and opted in)

Use the install doc or integration-test harness to deploy the **migrated** artifact.
Supplement tracing backend from `validation-stack.md` only when docs do not already
define `TRACING_HOST` / collector wiring.

### Runtime validation order (mandatory)

Umbrella §5.3 order — execute **in this order**:

```text
1. Stand health gate     → ../../opentelemetry-tracing-umbrella/recipes/stand-health-gate.md
2. Log error triage      → ../../opentelemetry-tracing-umbrella/recipes/log-error-triage.md
3. Business traffic      → non-suppressed endpoint (below)
4. Tracing assertions    → Jaeger/query API + log correlation
5. Pass/fail verdict     → only when steps 1–4 succeed
6. Post-validation cleanup → ../../opentelemetry-tracing-umbrella/recipes/validation-cleanup.md (when status is pass)
```

**Forbidden before step 1 passes:** querying Jaeger for pass/fail, declaring end-to-end
success, setting `runtime.status` to `pass`.

Common failure mode: probe or startup traffic exports spans while liveness kills
the pod (`CrashLoopBackOff`, `RESTARTS` climbing). That is **not** a passing
runtime tier.

### Stand health gate (step 1 — mandatory, run first)

Run [`../../opentelemetry-tracing-umbrella/recipes/stand-health-gate.md`](../../opentelemetry-tracing-umbrella/recipes/stand-health-gate.md) immediately
after deploy. Post the **L5 Stand health** brief before any tracing check.

| Check | Pass when |
| --- | --- |
| Rollout | `kubectl rollout status` succeeded for the SUT Deployment |
| Workload health | SUT pod `Running` and Ready `1/1` (no crash loops, no perpetual not-ready) |
| Stability | After a ≥60s observation window, Ready still `1/1` and restarts not increasing |
| Service endpoints | SUT Service endpoints non-empty |
| Dependencies | DB, Jaeger/collector, and other stand workloads Ready/healthy |
| Traffic path | Business HTTP `2xx` through the Service entrypoint (not in-pod bypass only) |

If any check fails, set `runtime.status` to `fail`. Record evidence under
`validationPlan.runtime.standHealth` and plan root `gaps`.

### Log error triage (step 2 — mandatory before tracing pass/fail)

After stand health passes, run
[`../../opentelemetry-tracing-umbrella/recipes/log-error-triage.md`](../../opentelemetry-tracing-umbrella/recipes/log-error-triage.md). Post the
**L5 Log errors** brief. Set `validationPlan.runtime.logErrorTriage` in the
migration plan JSON.

Do not declare runtime `pass` when `logErrorTriage.e2eBlocked` is true.

### Endpoint selection (step 3)

Exercise a **business endpoint that is NOT in the suppression list**. Do not
default to `/v3/api-docs`, `/q/*`, `/actuator/*`, or probe URLs.

### Tracing assertions (step 4)

The runtime tier passes only when **steps 1–2 pass** and tracing assertions
succeed:

- `service.name = <name>-<namespace>` (resolved value);
- `span.kind = server` for the exercised endpoint;
- propagation intact (`traceparent` or `b3`/`b3multi`); one `trace_id` across async hops if applicable;
- non-empty `traceId`/`spanId` in logs for the request;
- build provenance per [`../reference/build-preconditions.md`](../reference/build-preconditions.md);
- tracing backend healthy; no recurring export errors in SUT logs.

**Do not** report end-to-end success when:

- spans exist only from probe traffic on suppressed/failing paths;
- the app listens but readiness never passes;
- you validated OTLP export while the deployment remains unavailable or restart-prone.

If the user asks about log errors, answer with the classified verdict — never
"there are errors but it's fine" without triage evidence.

If the service never started because install/build was out of scope or blocked,
set `runtime.status` to `manual` or `fail` with the reason — not `pass` on
static/config alone.
