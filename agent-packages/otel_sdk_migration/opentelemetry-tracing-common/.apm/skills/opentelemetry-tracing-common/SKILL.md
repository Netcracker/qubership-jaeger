---
name: opentelemetry-tracing-common
description: Shared internal core for the OpenTelemetry tracing language packages (opentelemetry-tracing-java, opentelemetry-tracing-go, opentelemetry-tracing-python, opentelemetry-tracing-ts) — holds the cross-language capability, maturity, transformation, and validation layers plus the platform tracing contract. Do not start a tracing task here; this package has no discovery layer and no phase gates, so entering it directly skips the analysis a migration depends on. For any actual service work, start from the language package matching the repository and let it pull these layers in. Read this file directly only when editing the shared layers themselves, or when a language package sends you here.
---

# OpenTelemetry tracing common (shared core)

This package is the **shared core** pulled in by the language tracing skills
(`opentelemetry-tracing-java`, `opentelemetry-tracing-go`, `opentelemetry-tracing-python`,
`opentelemetry-tracing-ts`). **Start from the language `SKILL.md`** for end-to-end pipeline execution, phase gates, and
user briefs. Use this file for cross-language layer rules, schemas, and the platform contract.

**Read first:** [`reference/platform-tracing-guide.md`](reference/platform-tracing-guide.md) — mandatory binding rules
for configuration and validation tiers.

## Pipeline (cross-language)

```text
repository
   │
   ▼
[L1] Discovery        ──► discovery-result      (language package)
   │
   ▼
[L2] Capability       ──► capability-result     (common models/2)
   │
   ▼
[L3] Maturity         ──► maturity-result       (common models/3)
   │
   ▼
[L4] Transformation   ──► migration-plan        (common models/4 + language apply)
   │
   ▼
[L5] Validation       ──► validationPlan        (embedded in migration-plan; common models/5 + language runtime)
```

Each layer reads upstream artifacts only — not the raw repository again (except L1). Language packages extend the
common `models/` with local framework gates and execution recipes.

## Where the artifacts live (mandatory)

The five artifacts are **in-session data, not files**. Do not write them into the target repository, and do not create
them anywhere on disk unless the user asks for a file.

- Keep each artifact in the working context and pass it to the next layer. That separability is the point: L3 can cite
  the exact L2 field that produced its verdict.
- Show the user the prose brief (L1–L3) or the summary (L4–L5). Do not paste raw artifact JSON in chat unless the user
  asks for JSON.
- The JSON shape is the contract between layers, not a path. `schemas/` documents that shape so the layers agree on
  field names; nothing validates a file on disk.
- Phase 1 is read-only, so writing an artifact file into the target repository would break that rule for no benefit.

## Multi-language scope gate (mandatory — before Phase 2 / L4)

When discovery finds **two or more language families** in tracing scope (for example Java and Go services in the same
monorepo), or **two or more independent SUTs** the user did not narrow to one target:

1. **Stop after the L3 brief** — do not start Phase 2 until scope is explicit.
2. **Ask the user** which mode applies:
   - **Bulk** — migrate and validate every discovered language target in one session, with an ordered plan per target.
   - **Single** — the user picks one language family or one named service; L4–L5 apply only to that choice until the
     user expands scope.
3. Record the choice in chat and in the migration plan `gaps` or `validationPlan.runtime.scenario` (for example
   `scope: single — Go mesh-api only`).
4. If the user does not answer, emit a **plan-only** L4 document and keep `validationPlan.runtime.status` at `manual`.
   No repository edits.

The propagation-format question is asked **once for the whole scope**, in the L3 brief — never once per service. Rules
and timing: [`models/3-maturity.md`](models/3-maturity.md) §Propagation format. Each target then encodes the same
decision in its own framework syntax and list order.

This gate is cross-language; language packages enter it from Phase 2 (language `SKILL.md` §3.0).

## Ownership split

Common owns the shared layers:

- Layer 2 Capability — full.
- Layer 3 Maturity — full, including the decision matrix and the propagation-format question.
- Layer 4 Transformation — generic plan structure, §4.1–§4.5, documentation sync on apply.
- Layer 5 Validation — shared tiers, `validationPlan` shape, static and configuration checks, runtime gating rules.
- Shared L5 recipes: [`recipes/stand-health-gate.md`](recipes/stand-health-gate.md),
  [`recipes/log-error-triage.md`](recipes/log-error-triage.md),
  [`recipes/validation-stack.md`](recipes/validation-stack.md),
  [`recipes/validation-cleanup.md`](recipes/validation-cleanup.md).
- Shared reference: [`reference/platform-tracing-guide.md`](reference/platform-tracing-guide.md),
  [`reference/build-preconditions.md`](reference/build-preconditions.md),
  [`reference/service-installation-discovery.md`](reference/service-installation-discovery.md).
- Shared JSON schemas — capability, maturity, migration-plan.

Each language package owns the local parts:

- Layer 1 Discovery and `L1-discovery-result.schema.json`.
- `reference/detection-rules.md` and `reference/framework-coverage.md`.
- Layer 4 apply — framework gate plus the dependency, config, code, and async recipes.
- Layer 5 runtime execution — `recipes/fresh-build-and-image.md`, and the language deltas on the shared reference and
  validation-stack files.

## Shared layer files

| Layer | Common model | Language extension |
| --- | --- | --- |
| L2 | [`models/2-capability.md`](models/2-capability.md) | none — common only |
| L3 | [`models/3-maturity.md`](models/3-maturity.md) | none — common only |
| L4 | [`models/4-transformation.md`](models/4-transformation.md) | Step 0 framework gate, recipes, apply |
| L5 | [`models/5-validation.md`](models/5-validation.md) | install path, fresh build, language deltas |

## Shared schemas (common)

- [`schemas/L2-capability-result.schema.json`](schemas/L2-capability-result.schema.json)
- [`schemas/L3-maturity-result.schema.json`](schemas/L3-maturity-result.schema.json)
- [`schemas/L4-migration-plan.schema.json`](schemas/L4-migration-plan.schema.json) — includes the embedded
  `validationPlan`

`L1-discovery-result.schema.json` lives in each language package, because the discovery shape differs per language.
There are no per-language copies of the shared schemas — language layers link these files directly.
