# Layer 5 — Validation (shared)

**Goal:** define and execute `validationPlan` inside `migration-plan.json` — prove
the migrated stack is consistent in the repository (static + configuration) and,
when the user opts in, on a running deployment (runtime).

- **Input:** `migration-plan.json` (including proposed L4 edits), plus Layer 1–3
  artifacts for evidence (`discovery-result.json`, `capability-result.json`,
  `maturity-result.json`).
- **Output:** updated `validationPlan` statuses and evidence embedded in
  `migration-plan.json` →
  [`../schemas/L4-migration-plan.schema.json`](../schemas/L4-migration-plan.schema.json).
- **Language execution:** build, deploy, stand health, log triage, and tracing
  assertions — each language package (Java:
  [`opentelemetry-tracing-java`](../../opentelemetry-tracing-java/models/5-validation.md)).

## Validation tiers

| Tier | Needs running service | Default when plan is emitted |
| --- | --- | --- |
| **static** | No — inspect repository manifests and sources | Run checks; record `pass` / `fail` per row |
| **configuration** | No — inspect config bindings toward platform contract | Run checks; record `pass` / `fail` per row |
| **runtime** | Yes — user-named environment and deploy permission | `status: manual` until install path is known and user opts in |

Configuration tier must enforce the platform contract from
[`../reference/platform-tracing-guide.md`](../reference/platform-tracing-guide.md).

Status enum for every check and for `validationPlan.runtime.status`:
`pass`, `fail`, `manual`, `unknown` (schema `checkStatus`).

## Algorithm

1. **Emit the plan** (Layer 4 §4.5) — populate `validationPlan.static` and
   `validationPlan.configuration` with concrete checks derived from discovery and
   proposed L4 edits; set `validationPlan.runtime.status` to `manual` with
   `scenario`, `assertions`, and `manualInstruction` until runtime is in scope.
2. **Run static tier** — repository inspection only; no compile or deploy.
   Update each row's `status` and optional `detail` / `how`.
3. **Run configuration tier** — verify bindings against the platform contract;
   no deploy required.
4. **Runtime opt-in** — only after static/configuration are recorded and the
   user confirms a target environment. Follow the language install-discovery and
   fresh-build recipes before deploy.
5. **Runtime scenario** — when opted in, execute language steps in order:
   stand health → log-error triage → business traffic → tracing assertions →
   verdict (see §5.3).
6. **Record blockers** — build/registry issues, stand failures, skipped runtime,
   and triage blockers in plan root `gaps` (prose strings with evidence).
7. **Post-validation cleanup** — when `runtime.status` is `pass`, remove or
   revert **ephemeral** artifacts created only for L5 (see §5.4).
8. Validate the migration plan against
   [`../schemas/L4-migration-plan.schema.json`](../schemas/L4-migration-plan.schema.json).

Static and configuration tiers **never** require a fresh build or container image.
Do **not** set `validationPlan.runtime.status` to `pass` from static/config alone.

## `validationPlan` structure

Required on every migration plan (embedded Layer 5):

| Field | Type | Purpose |
| --- | --- | --- |
| `static` | `staticCheck[]` | Repo-level checks (dependencies, instrumentation mode, retired libs) |
| `configuration` | `staticCheck[]` | Platform contract bindings (export, propagation, sampler, service name, filters, log correlation) |
| `runtime` | object | Opt-in end-to-end scenario — see below |

Each `staticCheck`: `{ check, status, detail?, how? }`.

`runtime` object (required: `status`, `scenario`, `assertions`):

| Field | When to set |
| --- | --- |
| `status` | `manual` until opt-in; `pass` only when §5.3 gates succeed; `fail` when deploy or assertions fail; `unknown` when evidence is insufficient |
| `scenario` | Short prose: what will be deployed and exercised |
| `assertions` | Bullet list of tracing outcomes to verify (service name, span kind, propagation, log correlation) |
| `manualInstruction` | Required while `status` is `manual` — what the user must provide |
| `buildProvenance` | After language fresh-build — `source`, `matchesL4`, `detail`, optional `mavenCommand`, `imageTag`, `runnerJar`, `purgedImages` |
| `standHealth` | After stand-health gate — `passed`, readiness/restart evidence |
| `logErrorTriage` | After log scan — `verdict`, `e2eBlocked`, `findings`, etc. |

## §5.1 Static tier

Inspect the target repository only. Typical checks (language packages may add
framework-specific rows):

- **Single instrumentation path** — one active tracing mechanism; no parallel
  legacy + OTel export without an explicit migration plan row.
- **Retired libraries absent** — Jaeger client, OpenTracing, and other retired
  stacks from the platform guide are not on the dependency manifest.
- **Exporter present** — when migration targets export, OTel exporter/SDK deps
  exist and align with L4 `dependencyMigration`.
- **Propagation helpers** — when `b3` / `b3multi` is configured, required
  propagator extensions are present (language-specific coordinates).
- **Log correlation** — logging config or pattern includes `traceId` and
  `spanId` (or equivalent) when logging is discoverable.

Tier passes when every row is `pass`. Any `fail` fails the tier; use `unknown`
when discovery could not inspect the relevant file.

## §5.2 Configuration tier

Verify every binding rule from
[`../reference/platform-tracing-guide.md`](../reference/platform-tracing-guide.md)
against proposed or actual config (post-L4):

- `TRACING_ENABLED`, `TRACING_HOST`, sampler precedence
- OTLP exporter `http/protobuf` and endpoint shape
- Propagation — **two rows, never one**: the inject format matches what peers
  expect, and the extract set covers the peers that call in. Where the framework
  has a default (Spring Boot produces `[W3C]` unless told otherwise), check the
  effective value, not the presence of a key.
- Propagation composite order puts the **intended priority format** at the
  framework's winner end — the agent derives the end from the framework (first
  on Spring Boot, last on Quarkus / Pure Java / Go); the user only states which
  format should win
- Sampler `parentbased_traceidratio` (never `always_on`)
- `service.name=${service_name}-${namespace_name}` (resolved naming pattern)
- Probe / metrics / management endpoints excluded from trace export
- Mandatory `traceId` / `spanId` in logs

Tier passes when every row is `pass`. Non-1:1 mappings from L4 should already
be flagged in `configMigration[].note` and reflected in check `detail`.

## §5.3 Runtime tier (opt-in)

Runtime validation is **not** "build and deploy whatever we touched." Install
scope and test path come from discovery and install documentation in the
language package — do not invent a second pipeline.

### Prerequisites

- Layer 4 edits applied (or plan-only Level 5 with explicit runtime scope).
- Language **fresh-build** recipe succeeded when L4 changed the artifact —
  `buildProvenance.matchesL4` is `true`; never `pass` runtime on a pre-L4 or
  reused image without evidence.
- User specifies a **concrete environment** with deploy permission.
- If the user declines or cannot supply an environment, keep `runtime.status`
  as `manual`.

### Mandatory order (language recipes implement steps)

Execute in order; do not skip ahead because a backend already shows spans or
because a single in-process request succeeded:

```text
1. Stand health gate      — workload ready and stable
2. Log error triage       — classify ERROR/FATAL before pass/fail
3. Business traffic       — non-suppressed application endpoint
4. Tracing assertions     — backend query + log correlation
5. Pass/fail verdict      — only when steps 1–4 succeed
```

**Forbidden before step 1 passes:** declaring end-to-end success, querying the tracing
backend for a final pass/fail, setting `runtime.status` to `pass`.

Common failure mode: probe or startup traffic exports spans while the workload
remains unhealthy (crash loops, not Ready, climbing restarts). That is **not**
a passing runtime tier.

### Runtime `pass` requires

- Steps 1–4 completed in order.
- `standHealth.passed` is `true` (or equivalent evidence recorded).
- `logErrorTriage.e2eBlocked` is not `true`.
- Tracing assertions in `runtime.assertions` satisfied — including resolved
  `service.name`, server spans on the exercised endpoint, propagation intact,
  non-empty trace/span IDs in logs for the request, healthy export path.
- Build provenance documents a post-L4 artifact.

#### Propagation asserts the mechanism, not the outcome

"One `traceId` across services" is **not** a propagation check. It also passes
when the inject format is wrong (the receiver extracts leniently and joins the
trace anyway) and when the hierarchy is wrong (a stale header re-parents the
span). To assert propagation, the runtime tier needs:

- a **wire-header assert** — a receiver that dumps incoming headers, confirming
  the exact header names the service emits (`b3` vs `X-B3-*` vs `traceparent`);
- a **hierarchy assert** where a mesh or sidecar is in the path — parent/child
  relations in the backend, not just a shared trace ID.

Generalize this beyond propagation: **whenever a property has a lenient
fallback, end-to-end success does not prove the property is correct.** Assert
the mechanism directly.

### Runtime failure and blockers

- Stand or deploy failure → `runtime.status` `fail`; record evidence in
  `validationPlan.runtime.standHealth` and plan root `gaps`.
- Log triage blocks end-to-end → `fail` until resolved or reclassified with evidence.
- Install/build out of scope → `manual` or `fail` with reason — not `pass`.

Endpoint selection: exercise a **business** route not on the platform suppression
list (probes, actuator, OpenAPI, metrics paths).

## §5.4 Post-validation cleanup (mandatory after runtime `pass`)

When `validationPlan.runtime.status` is **`pass`**, remove or revert files
created **only** for L5 runtime — not L4 service changes (source, Helm of the
SUT, dependency manifests, or documentation synced on apply).

**Ephemeral** (typical — see [`recipes/validation-cleanup.md`](../recipes/validation-cleanup.md)):

- throwaway end-to-end manifests, install scripts, or compose/k8s overlays;
- local-only Dockerfiles or build helpers used solely for validation;
- temporary env files or copied credentials templates for the test stand.

**Retain** (do not delete as cleanup):

- any file that is part of the migrated service or its install path;
- artifacts the user asked to keep for repeat validation.

**Agent rules:**

1. During runtime, track ephemeral paths in chat or plan `gaps` as they are
   created.
2. After runtime `pass`, delete or revert ephemeral files; do **not** stage
   them for commit.
3. Post a short **L5 Cleanup** line in chat: files removed/reverted, or
   `none — no ephemeral artifacts`.
4. If cleanup is skipped (user asked to retain), record reason in `gaps`.

Language execution (shared recipes in this package):

- [`recipes/stand-health-gate.md`](../recipes/stand-health-gate.md)
- [`recipes/log-error-triage.md`](../recipes/log-error-triage.md)
- [`recipes/validation-cleanup.md`](../recipes/validation-cleanup.md)

Language packages supply fresh-build and validation-stack recipes only.

## User-facing summary (optional)

After updating `validationPlan`, a short **L5 Validation** brief in chat helps
reviewers (prose, not raw JSON): static/config pass or fail highlights, runtime
status, environment name, stand health verdict, log triage summary, and whether
tracing assertions succeeded. Brief templates live in the shared recipes above;
language skills add fresh-build briefs.
