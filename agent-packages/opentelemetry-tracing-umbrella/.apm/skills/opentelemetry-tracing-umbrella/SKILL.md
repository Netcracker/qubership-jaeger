---
name: opentelemetry-tracing-umbrella
description: Shared tracing core for all language packages. Use when designing or applying cross-language maturity, capability, decision, transformation, and validation logic for OpenTelemetry migration.
---

# OpenTelemetry tracing umbrella (shared core)

This package is the **shared core** pulled in by language tracing skills
(Java: `opentelemetry-tracing-java`). **Start from the language package
`SKILL.md`** for end-to-end pipeline execution, phase gates, and user briefs.
Use this file for cross-language layer rules, schemas, and the platform contract.

**Read first:** [`reference/platform-tracing-guide.md`](reference/platform-tracing-guide.md)
— mandatory binding rules for configuration and validation tiers.

## Pipeline (cross-language)

```text
repository
   │
   ▼
[L1] Discovery        ──► discovery-result.json      (language package)
   │
   ▼
[L2] Capability       ──► capability-result.json     (umbrella models/2)
   │
   ▼
[L3] Maturity         ──► maturity-result.json       (umbrella models/3)
   │
   ▼
[L4] Transformation   ──► migration-plan.json          (umbrella models/4 + language apply)
   │
   ▼
[L5] Validation       ──► validationPlan             (embedded in migration-plan; umbrella models/5 + language runtime)
```

Each layer reads upstream artifact(s) only — not the raw repository again
(except L1). Language packages stub or extend umbrella `models/` for local
framework gates and execution recipes.

## Ownership split

- **Umbrella owns (shared):**
  - Layer 2 Capability — full
  - Layer 3 Maturity — full (decision matrix in `models/3-maturity.md`)
  - Layer 4 Transformation — **generic plan structure**, §4.1–§4.5, documentation sync on apply
  - Layer 5 Validation — **shared tiers**, `validationPlan` shape, static/configuration checks, runtime gating rules
  - [`reference/platform-tracing-guide.md`](reference/platform-tracing-guide.md) and shared reference below
  - Shared JSON schemas (capability, maturity, migration-plan — listed below)
- **Language package owns (local):**
  - Layer 1 Discovery and `L1-discovery-result.schema.json`
  - [`reference/detection-rules.md`](reference/detection-rules.md) (per language)
  - Layer 4 **apply** — framework gate, dependency/config/code/async recipes
  - Layer 5 **runtime execution** — fresh build, deploy, stand health, log triage, tracing assertions
  - `recipes/` and language/framework support notes

## Shared layer files

| Layer | Umbrella model                                             | Language extension                       |
|-------|------------------------------------------------------------|------------------------------------------|
| L2    | [`models/2-capability.md`](models/2-capability.md)         | stub → umbrella                          |
| L3    | [`models/3-maturity.md`](models/3-maturity.md)             | stub → umbrella (matrix in model)        |
| L4    | [`models/4-transformation.md`](models/4-transformation.md) | Step 0 / recipes / apply                 |
| L5    | [`models/5-validation.md`](models/5-validation.md)         | install path, fresh-build, runtime order |

## Shared schemas (umbrella)

- [`schemas/L2-capability-result.schema.json`](schemas/L2-capability-result.schema.json)
- [`schemas/L3-maturity-result.schema.json`](schemas/L3-maturity-result.schema.json)
- [`schemas/L4-migration-plan.schema.json`](schemas/L4-migration-plan.schema.json) — includes embedded `validationPlan`

`L1-discovery-result.schema.json` lives in each **language package** (Layer 1 output).

Language packages may ship schema redirects (`allOf` + `$ref`) pointing here;
umbrella schemas are the source of truth.

## Shared reference

- [`reference/platform-tracing-guide.md`](reference/platform-tracing-guide.md) — platform contract and export topology
