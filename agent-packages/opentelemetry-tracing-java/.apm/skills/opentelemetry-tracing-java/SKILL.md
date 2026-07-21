---
name: opentelemetry-tracing-java
description: Audits distributed tracing in unknown Java services (Spring Boot, Quarkus, pure Java), scores maturity (levels 1-5), and produces OpenTelemetry migration and validation plans against the Qubership platform tracing contract. Use when the repository has no tracing, legacy tracing (Brave/Zipkin, Jaeger client, OpenTracing, Sleuth), hybrid or incomplete OTel, broken Kafka/async context propagation, failed OTLP export, or work touching TRACING_* variables, sampling, B3/b3multi/W3C propagation, traceId/spanId log correlation, Micrometer OTel bridges, Helm tracing values, or pom.xml OTel dependencies — including when the user only mentions tracing, spans, Jaeger, OpenTelemetry, or broken/missing traces without naming this skill. Prefer over generic OTel advice for any Java tracing change to code, config, Helm, or dependencies.
---

# OpenTelemetry tracing audit & migration engine (Java)

This skill is an **analysis pipeline**, not a single how-to. It takes an
unknown Java repository as input and produces five machine-readable
artifacts: a discovery profile, a capability assessment, a maturity verdict,
a migration plan, and a validation plan. Each artifact is the input of the
next stage, so the layers compose into one deterministic flow.

The platform target is the Qubership/NC tracing backend (services export via
the `nc-diagnostic-agent` proxy → Jaeger). The binding rules — contracted
`TRACING_*` parameters, OTLP/B3 standards, `parentbased_traceidratio` sampling,
`service.name` namespace convention, endpoint filtering, and mandatory
trace-IDs-in-logs — are defined in
[`opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md`](../opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md).
**Read that file before producing any artifact** — it is the source of truth
the layers below enforce (including export topology: `TRACING_HOST`, OTLP endpoint).

## 1. When to apply

Engage when the task touches any of:

- Assessing or enabling **distributed tracing** in a Java microservice
- **Legacy** tracing — Brave/Zipkin, Jaeger SDK, OpenTracing, Spring Cloud Sleuth
- **Hybrid** stacks — OpenTelemetry layered on top of a legacy tracer
- **Incomplete** OTel — API present but no SDK or exporter wired
- **Kafka / async** boundaries that break trace continuity
- Auditing **sampling** and **propagator** settings before a release
- Producing a **migration plan** to OpenTelemetry for review
- Best-effort Java frameworks not first-classed yet (Micronaut, Helidon, Vert.x, Jakarta EE, Dropwizard)

Do **not** use for Go, Python, or JS/TS services — separate packages apply.
This skill scopes to **application-level** instrumentation; cluster-side OTeC
and Jaeger topology is reference context, not the migration target.

## 2. Pipeline overview

```text
repository
   │
   ▼
[L1] Discovery   ──► discovery-result.json     (what exists)
   │
   ▼
[L2] Capability  ──► capability-result.json    (what actually works)
   │
   ▼
[L3] Maturity    ──► maturity-result.json      (Level 1..5 + action)
   │
   ▼
[L4] Transformation ─► migration-plan.json     (dependency/config/code/async)
   │
   ▼
[L5] Validation  ──► validation plan           (embedded in migration-plan.json)
```

Each layer reads only the artifact(s) before it, never the raw repository
again (except L1). This keeps every stage auditable: a wrong verdict can be
traced to the exact field of the upstream JSON that produced it.

### Layer responsibilities

| Layer             | File                                                       | Reads                  | Produces                             |
|-------------------|------------------------------------------------------------|------------------------|--------------------------------------|
| L1 Discovery      | [`models/1-discovery.md`](models/1-discovery.md)           | repository             | `discovery-result`                   |
| L2 Capability     | shared in `opentelemetry-tracing-umbrella`                 | discovery              | `capability-result`                  |
| L3 Maturity       | shared in `opentelemetry-tracing-umbrella`                 | discovery + capability | `maturity-result`                    |
| L4 Transformation | shared in `opentelemetry-tracing-umbrella`                 | all above              | `migration-plan`                     |
| L5 Validation     | shared in `opentelemetry-tracing-umbrella`                 | migration-plan         | `validationPlan` (in migration-plan) |

## 3. Execution order

Run the layers strictly in order. Do not skip ahead — a maturity verdict
without a capability assessment is a guess, and a migration plan without a
maturity verdict has no anchor.

### 3.0 Analysis phase gate (mandatory — before L4)

Split every **implement** run into two phases. Phase 1 is **read-only analysis**
so the user has material to read while Phase 2 runs.

#### Phase 1 — L1 + L2 + L3 (analysis only)

Complete all three layers and post **all three user-facing briefs** (§3.1) in
the agent chat **before** starting Phase 2.

During Phase 1 the agent **must not**:

- edit source, config, Helm, or docs in the target repository
- run build/package/image commands for the SUT
- deploy runtime manifests or start runtime end-to-end
- apply L4 transformation recipes

Phase 1 **may** use read-only repository inspection (`grep`, `read`, dependency
declarations in `pom.xml`, static config review). Emit JSON artifacts
(`discovery-result`, `capability-result`, `maturity-result`) and use their
findings to write the briefs. Briefs do **not** replace the JSON artifacts.

**Stop after the L3 brief** unless the user explicitly asked to skip analysis
(audit-only deliverable) or to proceed with implementation in the same turn.
When the user asked to implement (e.g. “add OTel SDK”), post the three briefs,
then continue to Phase 2 in the **same session** without re-running L1–L3
unless the repository changed.

**Multi-language repository:** if discovery spans **two or more language
families** or multiple SUTs, run the umbrella
[Multi-language scope gate](../opentelemetry-tracing-umbrella/SKILL.md)
— ask the user **bulk vs single target** before any L4 edit. Do not proceed to
Phase 2 without an explicit choice.

#### Phase 2 — L4 + L5 (implementation and validation)

Only after Phase 1 briefs are posted:

1. **Transformation (L4)** — apply dependency/config/code/docs edits.
2. **One fresh build** — see §3.2 (exactly **once** after L4, before runtime).
3. **Validation (L5)** — static/config tiers without recompiling; runtime opt-in.
   Runtime order: **stand health → log triage → tracing** (never Jaeger-first).

If the user only wanted an audit, stop after Phase 1 and set
`validationPlan.runtime.status` to `manual`.

### 3.0.1 Layer sequence (within Phase 1 and 2)

1. **Discovery** — scan dependencies, config, code (AST), instrumentation
   mode, and async boundaries. Emit `discovery-result.json`. Validate it
   against [`schemas/L1-discovery-result.schema.json`](schemas/L1-discovery-result.schema.json).
   Then post a **user-facing L1 brief** (see §3.1). *(Phase 1)*
2. **Capability** — derive *real* tracing capabilities (propagation, span
   quality, export) from discovery evidence. Emit `capability-result.json`.
   Then post a **user-facing L2 brief** (see §3.1). *(Phase 1)*
3. **Maturity** — apply the decision matrix in umbrella
   [`models/3-maturity.md`](../opentelemetry-tracing-umbrella/models/3-maturity.md)
   to land on **current** Level 1–5 and the recommended action; cite the matrix
   row. If L4 follows, state **target** level separately (usually Level 5).
   Emit `maturity-result.json`. Then post a **user-facing L3 brief** (see §3.1).
   *(Phase 1 — last step before any edits)*
4. **Transformation** — first fix the **framework family** and the
   instrumentation **mechanism** (the mandatory gate in
   [`models/4-transformation.md`](models/4-transformation.md): Quarkus requires
   the extension and forbids the Java agent), then apply dependency, config,
   code (mechanical + semantic), async-context, and **documentation** changes.
   Emit `migration-plan.json`. Pull concrete edits from [`recipes/`](recipes/).
   *(Phase 2)*
5. **Validation** — static + configuration tiers without a second full rebuild
   (see §3.2). Runtime is opt-in after the **single** post-L4 build; ask the
   user before cluster deploy (§3.3). Stand health and tracing assertions from
   [`models/5-validation.md`](models/5-validation.md). *(Phase 2)*

If private Maven registries block an install path documented elsewhere, record it
in `gaps` per [`reference/build-preconditions.md`](reference/build-preconditions.md)
— do not improvise agent overlays or stock-image workarounds.

If any layer's input is missing a field it requires, mark the dependent
output field `unknown` and record it under `gaps` — never invent evidence.

### 3.1 User-facing layer briefs (L1–L3, mandatory)

After each analysis layer **L1, L2, and L3** completes, post a short
**thesis-style summary in the agent chat** before moving to the next layer.
Users who finish a migration must see the current telemetry picture without
opening JSON. Keep each brief to 5–10 bullets; cite evidence paths where
non-obvious.

**L1 — Discovery brief** must cover:

- framework family and service name guess
- dependency buckets (`hasOtelApi/Sdk/Exporter`, `hasLegacy`, key artifacts)
- export / sampling config (or "none configured")
- **propagation** — say it as two directions, in plain words, and name the source
  of each: e.g. "accepts W3C, B3 and B3-multi inbound; sends **W3C only**
  outbound — both are Spring Boot defaults, nothing is set in config". Where the
  value is a framework default rather than a written key, say so — "not
  configured" is not the same as "not propagating". Add "(changing this needs a
  rebuild)" for Quarkus.
- instrumentation mode (`auto` / `manual` / `mixed` / `none`)
- async-boundary hotspots (Kafka, executors, reactive) or "none found"
- **Platform guide** — only if gaps exist: plain-language issues (e.g. "logs lack
  trace IDs", "export still points at Zipkin, not OTLP to the collector") with
  file paths. Do **not** list `platformContract` JSON fields or PASS/FAILED tokens.

**L2 — Capability brief** must cover:

- propagation verdict per component (HTTP, Kafka, async) — **plain language**
  (e.g. "Kafka loses context on async handoff"), not `PASS`/`FAILED` enums
- **inbound vs outbound compatibility**, stated separately — whether what the
  service *sends* matches what its peers read is a different answer from whether
  it *understands* what arrives. Call out the asymmetric case explicitly, since
  it is invisible in testing: "incoming traces are picked up fine, but outgoing
  calls emit a format B3-only peers will ignore"
- span quality (lifecycle, attributes, errors) at a high level
- export path (exporter, endpoint, protocol, target guess) in prose
- **Platform guide compliance** — summarize contract gaps or confirmations in
  human terms (service naming, sampling, B3 propagation, log correlation, export
  shape). Do **not** paste `platformContract` facets or verdict codes in chat

**L3 — Maturity brief** must cover (plain language for the user — **no**
`recommendedAction` slugs like `introduce-otel` in chat; those belong in JSON
only). Decision matrix and level wording:
umbrella [`models/3-maturity.md`](../opentelemetry-tracing-umbrella/models/3-maturity.md).

- **Current level** — level number + name + one sentence what it means for this
  repository (e.g. “Level 2 — Legacy tracing: the service still uses Spring Cloud
  Sleuth; OpenTelemetry is not the active export path”).
- **Recommended work** — what to do next in prose (e.g. “Migrate from legacy
  tracing to OpenTelemetry per the platform contract”), not a schema enum.
- **Target level** (L4 planned only) — where the service should land after a
  successful migration, usually “Level 5 — Working OTel: OTLP export to the
  platform collector, no legacy libraries”. Omit for audit-only runs.
- **Migration path** (L4 planned only, mandatory) — one line:
  **`Migration path: Level <current> → Level <target>`** (e.g.
  `Migration path: Level 2 → Level 5`). Not shorthand “1→2” — Level 2 means
  legacy tracing **today**.
- One-line rationale with evidence paths (file or config cited).
- Blockers or `gaps` that affect the transformation plan.

Do **not** use shorthand like “1→2”; Level 2 means **legacy** tracing only.

Example brief shape:

```markdown
### L3 Maturity — order-service
- **Current level:** Level 2 — Legacy tracing — Spring Cloud Sleuth is on the classpath; no working OTel export.
- **Recommended work:** Migrate to OpenTelemetry: remove Sleuth, add Micrometer OTel bridge and OTLP export per platform contract.
- **Target level:** Level 5 — Working OTel — single OTel stack, traces reach the collector, legacy libs removed.
- **Migration path:** Level 2 → Level 5
- **Rationale:** `pom.xml` declares Sleuth; no working OTLP export path is configured.
- **Blockers:** none
```

Do **not** skip these briefs when implementing changes (L4) — they are the
handoff record for reviewers and for users returning to close the migration.

### 3.2 Fresh build and image (once per session, after L4)

When Layer 4 edits exist, run
[`recipes/fresh-build-and-image.md`](recipes/fresh-build-and-image.md) **exactly
once** in the session — **after all L4 file edits**, **before** the first SUT
runtime deploy for end-to-end.

#### One build rule

| When | Maven / image |
| --- | --- |
| Phase 1 (L1–L3) | **Forbidden** — no compile “to see if it works” |
| After L4 completes | **Required once** — `mvn clean package` + new image tag |
| L5 static/config checks | **No rebuild** — inspect repository + post-L4 artifact on disk |
| L5 runtime end-to-end | **Reuse** the post-L4 artifact; **verify** provenance (§3.2.1) |
| L4 edits after first build | **Rebuild once** — new single build replaces the prior |

**Forbidden:** running `mvn clean package` before L4; running a **second**
full rebuild for end-to-end when the post-L4 build already succeeded and L4 files are
unchanged; deploying pre-existing tags (`:e2e`, `:local`, stock `:latest`) without
the post-L4 build.

Steps (full detail in the recipe):

1. Purge stale `target/` and cached SUT images in the active runtime image store.
2. `mvn clean package` (or install-doc command) — must exit 0.
3. Build a **new** container image with a **session-unique tag** and make it
   available in the selected runtime environment.
4. Post the **L5 Fresh build** brief from the recipe.

If Maven fails (registry, credentials), set `runtime.status` to `manual` — **never**
substitute a stale image or a pre-L4 build.

#### 3.2.1 Build provenance check (before runtime deploy)

Before runtime deploy, confirm the runnable artifact reflects **post-L4** state:

- Runner JAR (or equivalent) **mtime is after** the last L4 edit in the session.
- `validationPlan.runtime.buildProvenance.matchesL4` is `true`.
- Image tag recorded in the brief matches the manifest about to be applied.

If the only build predates L4, **do not deploy** — run the single post-L4 build
from §3.2 instead of re-auditing.

### 3.3 Runtime end-to-end opt-in (mandatory after build)

When Layer 4 changes are applied and the **fresh build** (§3.2) succeeds,
**stop and ask the user** before any runtime deploy:

> Static build is green. Run runtime end-to-end with a minimal tracing stack?
> Please provide the target environment and deployment scope where runtime
> deploy is allowed.

Rules:

- **Never** autonomously assume a runtime environment is available — the user
  must name the target environment.
- Point the user (and yourself) at the **dev-minimal profile** in
  [`recipes/validation-stack.md`](recipes/validation-stack.md): Jaeger all-in-one +
  `nc-diagnostic-agent` Service + SUT dependencies from install docs.
- If the user declines or gives no environment, set `validationPlan.runtime.status`
  to `manual` — static/config alone is **not** end-to-end success.
- Do **not** claim end-to-end passed from bypass traffic into unhealthy workloads, from
  spans produced only by failing probes, when service endpoints are not ready,
  or when the SUT pod is not Ready `1/1` with stable restarts.

### 3.4 Stand health gate (mandatory — first after deploy)

Immediately after runtime deploy, run
[`recipes/stand-health-gate.md`](../opentelemetry-tracing-umbrella/recipes/stand-health-gate.md) **before** Jaeger
queries or tracing pass/fail.

Rules:

- Execute `kubectl rollout status`, verify Ready `1/1`, non-empty endpoints, and
  a ≥60s stability window (re-check restarts).
- Post the **L5 Stand health** brief before any tracing check.
- Set `validationPlan.runtime.standHealth.passed=false` and `runtime.status` to
  `fail` when the pod is `CrashLoopBackOff`, not Ready, restart-prone, or
  endpoints are empty.
- **Jaeger spans alone never override a failed stand health gate** — probe
  traffic on a crash-looping pod can still export traces.

### 3.5 Log error brief (mandatory — after stand health, before tracing pass/fail)

After stand health passes, run
[`recipes/log-error-triage.md`](../opentelemetry-tracing-umbrella/recipes/log-error-triage.md) before Jaeger
pass/fail and before setting `validationPlan.runtime.status`. Post a short
**L5 Log errors** block (5–8 bullets): verdict, active vs stale findings, end-to-end
impact, evidence.

Rules:

- Classify every distinct `ERROR`/`FATAL` (and OTel export failures) — do not
  leave log errors unmentioned when the user asks or when declaring pass/fail.
- **`stale`** — previous pod/container or pre-fix boot only; absent since current
  pod Ready.
- **`benign`** — active but outside L4 tracing scope **and** business endpoint +
  span export succeed; cite why.
- **`blocks-e2e`** — active and breaks stand health or tracing assertions.
- Set `validationPlan.runtime.logErrorTriage.e2eBlocked=true` when any finding
  blocks; runtime `pass` is forbidden until resolved or reclassified with evidence.

Also record **build provenance** (fresh Maven vs reused image) per
[`reference/build-preconditions.md`](reference/build-preconditions.md) and
[`recipes/fresh-build-and-image.md`](recipes/fresh-build-and-image.md). Reused
image without L4 rebuild in this session → runtime at most `fail`.

### 3.6 Post-validation cleanup (mandatory after runtime `pass`)

When `validationPlan.runtime.status` is `pass`, run
[`recipes/validation-cleanup.md`](../opentelemetry-tracing-umbrella/recipes/validation-cleanup.md): remove or
revert ephemeral L5-only files (end-to-end manifests, throwaway scripts, local-only
Dockerfiles). Do **not** delete L4 service changes. Post an **L5 Cleanup** line
in chat. See umbrella [`models/5-validation.md`](models/5-validation.md) §5.4.

## 4. Output contract

A complete run yields a single JSON document per layer, all conforming to
the schemas in [`schemas/`](schemas/):

- `discovery-result.json` → [`schemas/L1-discovery-result.schema.json`](schemas/L1-discovery-result.schema.json)
- `capability-result.json` → [`schemas/L2-capability-result.schema.json`](schemas/L2-capability-result.schema.json)
- `maturity-result.json` → [`schemas/L3-maturity-result.schema.json`](schemas/L3-maturity-result.schema.json)
- `migration-plan.json` → [`schemas/L4-migration-plan.schema.json`](schemas/L4-migration-plan.schema.json)
  (includes the embedded `validationPlan`)

Keep JSON artifacts as the machine contract for the skill and reviewers. In
agent chat, present concise prose briefs and do not paste raw artifact JSON
unless the user explicitly asks for it.

## 5. Non-negotiable rules

| Rule | Reason |
| --- | --- |
| Platform contract is binding | Enforce umbrella [`platform-tracing-guide.md`](../opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md): `TRACING_*`, OTLP `http/protobuf`, `b3multi`, `parentbased_traceidratio`, `${name}-${namespace}`, probe/metrics exclusion, log correlation |
| Evidence-first | Every claim in an artifact cites a file/line or env key |
| No semantic auto-rename | Attribute renames to semconv are **proposed**, never applied without confirmation — see umbrella [`models/4-transformation.md`](../opentelemetry-tracing-umbrella/models/4-transformation.md) §4.3 |
| One tracing stack | A migration plan must end with a single active tracer; no Brave/Jaeger client layered on OTel |
| Sampling & propagation are mandatory | The validation plan fails if either is unknown or unverified |
| Preserve intent | Keep service names, sampling intent, and peer-compatible propagation across the migration |
| Confirm the export target | `TRACING_HOST` default is `nc-diagnostic-agent`; confirm proxy/collector for the runtime environment — see umbrella [`platform-tracing-guide.md`](../opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md) §Export |
| Defer versions | Read versions from the repository's `pom.xml`/BOM, never hardcode them |
| Spring Boot 4 OTLP starter | Parent 4.x requires `spring-boot-micrometer-tracing-opentelemetry` **and** Boot 4 `management.tracing.export.*` keys — see [`recipes/dependency-migration.md`](recipes/dependency-migration.md) |
| Sync documentation on L4 edits | When L4 changes deps/config/Helm/env, update readme, install notes, or Helm docs — see umbrella [`models/4-transformation.md`](../opentelemetry-tracing-umbrella/models/4-transformation.md) §Documentation sync |
| Fresh build before runtime | **One** `mvn clean package` + image **after L4** only — [`recipes/fresh-build-and-image.md`](recipes/fresh-build-and-image.md) |
| End-to-end only when stand is healthy | Runtime `pass` requires stand health (§3.4) before Jaeger, log triage (§3.5), fresh build, provenance — see [`models/5-validation.md`](models/5-validation.md) |
| No Jaeger-first pass | Spans in Jaeger while SUT crash-loops or is not Ready do not count as end-to-end pass |

## 6. File index

- Layers: [`models/`](models/) — `1-discovery` … `5-validation`
- Schemas: [`schemas/`](schemas/) — four JSON Schema documents
- **Shared core package:** `agent-packages/opentelemetry-tracing-umbrella/`
- **Platform contract (read first):** shared in umbrella
- Decision logic: shared in umbrella
- Detection signatures: [`reference/detection-rules.md`](reference/detection-rules.md)
- Quarkus platform wiring (`TRACING_ENABLED`, OTLP URL): [`reference/quarkus-platform-contract.md`](reference/quarkus-platform-contract.md)
- Build/registry gap notes: [`reference/build-preconditions.md`](reference/build-preconditions.md)
- Service install discovery (L5): [`reference/service-installation-discovery.md`](reference/service-installation-discovery.md)
- Code migration policy: umbrella `models/4-transformation.md` §4.3
- Platform export grounding: umbrella [`platform-tracing-guide.md`](../opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md)
- Migration recipes: [`recipes/`](recipes/) — [`recipes/fresh-build-and-image.md`](recipes/fresh-build-and-image.md),
  [`recipes/validation-stack.md`](recipes/validation-stack.md); shared L5 in umbrella
  [`recipes/stand-health-gate.md`](../opentelemetry-tracing-umbrella/recipes/stand-health-gate.md),
  [`recipes/log-error-triage.md`](../opentelemetry-tracing-umbrella/recipes/log-error-triage.md),
  [`recipes/validation-cleanup.md`](../opentelemetry-tracing-umbrella/recipes/validation-cleanup.md)
