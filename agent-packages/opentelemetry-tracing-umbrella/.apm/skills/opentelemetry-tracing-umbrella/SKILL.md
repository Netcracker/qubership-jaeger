---
name: opentelemetry-tracing-umbrella
description: Shared internal core for the OpenTelemetry tracing language packages (opentelemetry-tracing-java, opentelemetry-tracing-go, opentelemetry-tracing-python) — holds the cross-language capability, maturity, transformation, and validation layers plus the platform tracing contract. Do not start a tracing task here; this package has no discovery layer and no phase gates, so entering it directly skips the analysis a migration depends on. For any actual service work, start from the language package matching the repository and let it pull these layers in. Read this file directly only when editing the shared layers themselves, or when a language package sends you here.
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

## Multi-language scope gate (mandatory — before Phase 2 / L4)

When discovery finds **two or more language families** in tracing scope (e.g.
Java and Go services in the same repository or monorepo), or **two or more
independent SUTs** the user did not narrow to one target:

1. **Stop after the L3 brief** — do not start Phase 2 until scope is explicit.
2. **Ask the user** which mode applies:
   - **Bulk** — migrate/validate all discovered language targets in one session
     (ordered plan per target).
   - **Single** — user picks **one** language family or one named service; L4–L5
     apply only to that choice until the user expands scope.
3. Record the choice in chat and in `migration-plan.json` `gaps` or
   `validationPlan.runtime.scenario` (e.g. `scope: single — Go mesh-api only`).
   **Ask the propagation-format question here too, once for the whole scope**,
   when any target has no format configured — it is a fleet decision, not a
   per-service one, and asking per service produces inconsistent answers across
   the very services that must interoperate. Each target then encodes the same
   decision in its own framework syntax and list order. Rules:
   [`reference/platform-tracing-guide.md`](reference/platform-tracing-guide.md)
   §Propagation.
4. If the user does not answer, emit a **plan-only** L4 document and keep
   `validationPlan.runtime.status` at `manual` — **no repository edits**.

This gate is cross-language; language packages reference it from Phase 2 entry
(Java/Go: root `SKILL.md` §3.0).

## Ownership split

- **Umbrella owns (shared):**
  - Layer 2 Capability — full
  - Layer 3 Maturity — full (decision matrix in `models/3-maturity.md`)
  - Layer 4 Transformation — **generic plan structure**, §4.1–§4.5, documentation sync on apply
  - Layer 5 Validation — **shared tiers**, `validationPlan` shape, static/configuration checks, runtime gating rules
  - Shared L5 runtime recipes:
    [`recipes/stand-health-gate.md`](recipes/stand-health-gate.md),
    [`recipes/log-error-triage.md`](recipes/log-error-triage.md),
    [`recipes/validation-cleanup.md`](recipes/validation-cleanup.md)
  - [`reference/platform-tracing-guide.md`](reference/platform-tracing-guide.md) and shared reference below
  - Shared JSON schemas (capability, maturity, migration-plan — listed below)
- **Language package owns (local):**
  - Layer 1 Discovery and `L1-discovery-result.schema.json`
  - `reference/detection-rules.md` in each **language package** (Layer 1; not in umbrella)
  - Layer 4 **apply** — framework gate, dependency/config/code/async recipes
  - Layer 5 **runtime execution** — fresh build, deploy, validation-stack; tracing assertions
  - `recipes/` for L4 apply and language-specific L5 (fresh-build, validation-stack)

## Shared layer files

| Layer | Umbrella model                                             | Language extension                                |
|-------|------------------------------------------------------------|---------------------------------------------------|
| L2    | [`models/2-capability.md`](models/2-capability.md)         | stub → umbrella                                   |
| L3    | [`models/3-maturity.md`](models/3-maturity.md)             | stub → umbrella (matrix in model)                 |
| L4    | [`models/4-transformation.md`](models/4-transformation.md) | Step 0 / recipes / apply                          |
| L5    | [`models/5-validation.md`](models/5-validation.md)         | install path, fresh-build; shared runtime recipes |

## Shared schemas (umbrella)

- [`schemas/L2-capability-result.schema.json`](schemas/L2-capability-result.schema.json)
- [`schemas/L3-maturity-result.schema.json`](schemas/L3-maturity-result.schema.json)
- [`schemas/L4-migration-plan.schema.json`](schemas/L4-migration-plan.schema.json) — includes embedded `validationPlan`

`L1-discovery-result.schema.json` lives in each **language package** (Layer 1 output).

Language packages may ship schema redirects (`allOf` + `$ref`) pointing here;
umbrella schemas are the source of truth.

## Shared reference

- [`reference/platform-tracing-guide.md`](reference/platform-tracing-guide.md) — platform contract and export topology
