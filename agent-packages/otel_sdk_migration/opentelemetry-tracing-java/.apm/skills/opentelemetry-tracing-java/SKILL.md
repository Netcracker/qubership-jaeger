---
name: opentelemetry-tracing-java
description: Audits distributed tracing in unknown Java services (Spring Boot, Quarkus, pure Java), scores maturity (levels 1-5), and produces OpenTelemetry migration and validation plans against the Qubership platform tracing contract. Use when the repository has no tracing, legacy tracing (Brave/Zipkin, Jaeger client, OpenTracing, Sleuth), hybrid or incomplete OTel, broken Kafka/async context propagation, failed OTLP export, or work touching TRACING_* variables, sampling, B3/b3multi/W3C propagation, traceId/spanId log correlation, Micrometer OTel bridges, Helm tracing values, or pom.xml OTel dependencies — including when the user only mentions tracing, spans, Jaeger, OpenTelemetry, or broken/missing traces without naming this skill. Prefer over generic OTel advice for any Java tracing change to code, config, Helm, or dependencies.
---

# OpenTelemetry tracing audit and migration engine (Java)

This skill is an analysis pipeline. It takes an unknown Java repository as input and produces five artifacts: a
discovery profile, a capability assessment, a maturity verdict, a migration plan, and a validation plan. Each artifact
is the input of the next stage, so the layers compose into one deterministic flow.

Read the common platform contract first:
[`platform-tracing-guide.md`](../opentelemetry-tracing-common/reference/platform-tracing-guide.md) — the binding source
for `TRACING_*` parameters, OTLP export shape, propagation, sampling, service naming, endpoint filtering, and log
correlation. The platform target is the Qubership/NC tracing backend: services export through the
`nc-diagnostic-agent` proxy to Jaeger.

The artifacts are in-session data, never files on disk — common
[`SKILL.md`](../opentelemetry-tracing-common/SKILL.md) §Where the artifacts live.

## 1. When to apply

- assessing or enabling **distributed tracing** in a Java service;
- **legacy** tracing — Brave/Zipkin, Jaeger client, OpenTracing, Spring Cloud Sleuth;
- **hybrid** stacks — OpenTelemetry layered on top of a legacy tracer;
- **incomplete** OTel — API present but no SDK or exporter wired;
- **Kafka or async** boundaries that break trace continuity;
- auditing **sampling** and **propagator** settings before a release;
- producing a **migration plan** for review;
- best-effort Java frameworks not first-classed yet — see
  [`reference/framework-coverage.md`](reference/framework-coverage.md).

Do not use for Go, Python, or TypeScript services — separate packages apply. This skill scopes to **application-level**
instrumentation; cluster-side collector and Jaeger topology is reference context, not the migration target.

## 2. Pipeline overview

```text
repository
   │
   ▼
[L1] Discovery   ──► discovery-result     (what exists)
   │
   ▼
[L2] Capability  ──► capability-result    (what actually works)
   │
   ▼
[L3] Maturity    ──► maturity-result      (Level 1..5 + action)
   │
   ▼
[L4] Transformation ─► migration-plan     (dependency/config/code/async)
   │
   ▼
[L5] Validation  ──► validationPlan       (embedded in migration-plan)
```

Each layer reads only the artifacts before it, never the raw repository again (except L1). That keeps every stage
auditable: a wrong verdict traces back to the exact field of the upstream artifact that produced it.

Layer ownership:

- L1: this package — [`models/1-discovery.md`](models/1-discovery.md), Java detection rules and recipes;
- L2–L5: common shared logic, with the Java gates and runtime execution below.

## 3. Execution order

Run the layers strictly in order. A maturity verdict without a capability assessment is a guess, and a migration plan
without a maturity verdict has no anchor.

If any layer's input is missing a field it requires, mark the dependent output field `unknown` and record it under
`gaps` — never invent evidence.

### 3.0 Analysis phase gate (mandatory — before L4)

**Phase 1 (read-only):** L1, L2, L3, and all three user briefs.

During Phase 1 the agent must not edit source, config, Helm, or docs; run build, package, or image commands; deploy
runtime manifests; or apply L4 recipes. Read-only inspection is fine — `grep`, `read`, `pom.xml` dependency
declarations, static config review.

**Stop after the L3 brief** unless the user asked for implementation. When they did (for example "add the OTel SDK"),
post the three briefs and continue to Phase 2 in the **same session**, without re-running L1–L3 unless the repository
changed. An audit-only run ends at the L3 brief: it produces no migration plan, and therefore no
`validationPlan` — write the plan only if the user asks for one.

**Multi-language repository:** when discovery spans two or more language families or several SUTs, run the common
[multi-language scope gate](../opentelemetry-tracing-common/SKILL.md) — ask **bulk vs single target** before any L4
edit. Do not proceed without an explicit choice.

**Phase 2 (implementation):** L4, then exactly one post-L4 build (§3.2), then L5 validation. Runtime order is
**stand health → log triage → tracing** — never Jaeger first.

### 3.0.1 Layer sequence

1. **Discovery** — scan dependencies, config, code (AST), instrumentation mode, and async boundaries. Emit
   `discovery-result` with every field listed in [`schemas/L1-discovery-result.schema.json`](schemas/L1-discovery-result.schema.json).
   Post the L1 brief. *(Phase 1)*
2. **Capability** — derive the real capabilities from discovery evidence per common
   [`models/2-capability.md`](../opentelemetry-tracing-common/models/2-capability.md). Post the L2 brief. *(Phase 1)*
3. **Maturity** — apply the decision matrix in common
   [`models/3-maturity.md`](../opentelemetry-tracing-common/models/3-maturity.md) and cite the matrix row. Post the L3
   brief. *(Phase 1 — last step before any edits)*
4. **Transformation** — first fix the framework family and the instrumentation mechanism (the mandatory gate in
   [`models/4-transformation.md`](models/4-transformation.md): Quarkus requires the extension and forbids the Java
   agent), then apply dependency, config, code, async-context, and documentation changes. Pull concrete edits from
   [`recipes/`](recipes/). *(Phase 2)*
5. **Validation** — static and configuration tiers without a second rebuild; runtime is opt-in after the single
   post-L4 build. See [`models/5-validation.md`](models/5-validation.md). *(Phase 2)*

### 3.1 User-facing briefs (mandatory)

Content and rules for all three briefs: common
[`reference/user-briefs.md`](../opentelemetry-tracing-common/reference/user-briefs.md).

Java adds to the L1 brief:

- **framework family** — Spring Boot 3, Spring Boot 4, Quarkus, or Pure Java. Boot 3 and Boot 4 are different targets,
  not one "Spring Boot";
- **instrumentation mechanism** — extension, starter bridge, manual SDK, or `-javaagent`;
- "(changing this needs a rebuild)" on any Quarkus propagation or export value, because `quarkus.otel.*` is build-time.

### 3.2 Fresh build and image (once per session, after L4)

Run [`recipes/fresh-build-and-image.md`](recipes/fresh-build-and-image.md) **exactly once** — after all L4 edits,
before the first runtime deploy.

| When | Maven / image |
| --- | --- |
| Phase 1 (L1–L3) | **Forbidden** — no compile "to see if it works" |
| After L4 completes | **Required once** — `mvn clean package` plus a new image tag |
| L5 static/config checks | **No rebuild** — inspect the repository and the post-L4 artifact on disk |
| L5 runtime end-to-end | **Reuse** the post-L4 artifact; verify provenance |
| L4 edits after the first build | **Rebuild once** — the new build replaces the prior one |

Before runtime deploy, confirm the runnable artifact reflects post-L4 state: the runner JAR mtime is after the last L4
edit, `validationPlan.runtime.buildProvenance.matchesL4` is `true`, and the image tag in the brief matches the manifest
about to be applied. If the only build predates L4, do not deploy — run the single post-L4 build instead of
re-auditing.

If Maven fails on registry or credentials, set `runtime.status` to `manual` — never substitute a stale image or a
pre-L4 build. Blocker handling: common
[`reference/build-preconditions.md`](../opentelemetry-tracing-common/reference/build-preconditions.md) and the
[Java delta](reference/build-preconditions.md).

### 3.3 Runtime end-to-end opt-in (mandatory after build)

When the fresh build succeeds, **stop and ask** before any runtime deploy:

> Static build is green. Run runtime end-to-end with a minimal tracing stack? Please provide the target environment and
> deployment scope where runtime deploy is allowed.

Never assume a runtime environment is available — the user must name it. If they decline or give no environment, set
`validationPlan.runtime.status` to `manual`; static and configuration alone are **not** end-to-end success.

The stand itself, the runtime order, and teardown: common
[`recipes/validation-stack.md`](../opentelemetry-tracing-common/recipes/validation-stack.md) and the
[Java delta](recipes/validation-stack.md).

## 4. Output contract

A complete run yields one artifact per layer:

- `discovery-result` → [`schemas/L1-discovery-result.schema.json`](schemas/L1-discovery-result.schema.json)
- `capability-result` → common [`schemas/L2-capability-result.schema.json`](../opentelemetry-tracing-common/schemas/L2-capability-result.schema.json)
- `maturity-result` → common [`schemas/L3-maturity-result.schema.json`](../opentelemetry-tracing-common/schemas/L3-maturity-result.schema.json)
- `migration-plan` → common [`schemas/L4-migration-plan.schema.json`](../opentelemetry-tracing-common/schemas/L4-migration-plan.schema.json),
  including the embedded `validationPlan`

## 5. Non-negotiable rules

| Rule | Reason |
| --- | --- |
| Platform contract is binding | Enforce `TRACING_*`, OTLP `http/protobuf`, `b3multi`, `parentbased_traceidratio`, `${name}-${namespace}`, probe/metrics exclusion, log correlation |
| Evidence-first | Every claim in an artifact cites a file, line, or env key |
| No semantic auto-rename | Attribute renames to semconv are proposed, never applied without confirmation |
| One tracing stack | A plan must end with a single active tracer; no Brave or Jaeger client layered on OTel |
| Sampling and propagation are mandatory | Validation fails if either is unknown or unverified |
| Preserve intent | Keep service names, sampling intent, and peer-compatible propagation across the migration |
| Confirm the export target | `TRACING_HOST` defaults to `nc-diagnostic-agent`; confirm the proxy for the runtime environment |
| Defer versions | Read versions from the repository's `pom.xml` or BOM, never hardcode them |
| Spring Boot 4 OTLP starter | Parent 4.x requires `spring-boot-micrometer-tracing-opentelemetry` **and** Boot 4 `management.tracing.export.*` keys — [`recipes/dependency-migration.md`](recipes/dependency-migration.md) |
| Quarkus forbids the agent | `quarkus-opentelemetry` instruments at build time; the runtime `-javaagent` double-instruments and breaks Vert.x |
| Sync documentation on L4 edits | When L4 changes deps, config, Helm, or env, update the readme, install notes, or Helm docs in the same pass |
| Fresh build before runtime | One `mvn clean package` plus image, after L4 only |
| End-to-end only when the stand is healthy | Runtime `pass` requires stand health and log triage before Jaeger |
| No Jaeger-first pass | Spans in Jaeger while the SUT crash-loops or is not Ready are not an end-to-end pass |

## 6. File index

- Layers: [`models/`](models/) — `1-discovery`, `4-transformation`, `5-validation` (L2 and L3 are common)
- Schema: [`schemas/L1-discovery-result.schema.json`](schemas/L1-discovery-result.schema.json)
- Detection signatures: [`reference/detection-rules.md`](reference/detection-rules.md)
- Framework coverage: [`reference/framework-coverage.md`](reference/framework-coverage.md)
- Quarkus platform wiring: [`reference/quarkus-platform-contract.md`](reference/quarkus-platform-contract.md)
- Build blockers (Java delta): [`reference/build-preconditions.md`](reference/build-preconditions.md)
- Recipes: [`recipes/`](recipes/) — L4 apply, `fresh-build-and-image`, and the `validation-stack` delta
- Shared core: [`opentelemetry-tracing-common/SKILL.md`](../opentelemetry-tracing-common/SKILL.md)
