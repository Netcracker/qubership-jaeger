# opentelemetry-tracing-common

Shared tracing core for the language-specific tracing skills. It is an internal package: nothing starts a tracing task
here, and it ships no instruction rule, because the language skills pull it in.

Part of the multi-language tracing program — see [`../README.md`](../README.md).

## Pipeline

Layers L2–L5 live here; L1 and runtime execution live in each language package. See
[`.apm/skills/opentelemetry-tracing-common/SKILL.md`](.apm/skills/opentelemetry-tracing-common/SKILL.md) for the full
ownership split and the artifact chain.

## Contents

- **Models:** `models/2-capability.md`, `models/3-maturity.md`, `models/4-transformation.md`,
  `models/5-validation.md`
- **Shared L5 recipes:** `recipes/stand-health-gate.md`, `recipes/log-error-triage.md`,
  `recipes/validation-stack.md`, `recipes/validation-cleanup.md`
- **Shared reference:** `reference/platform-tracing-guide.md` (the binding contract),
  `reference/user-briefs.md` (L1–L3 brief templates), `reference/build-preconditions.md`,
  `reference/service-installation-discovery.md`
- **Cross-cutting gates:** multi-language scope and the artifact-location rule (`SKILL.md`), the
  propagation-format question (`models/3-maturity.md`), post-validation cleanup (`models/5-validation.md` §5.4)
- **Schemas:** `schemas/L2-capability-result.schema.json`, `schemas/L3-maturity-result.schema.json`. The migration
  plan has none — its fields are tabulated in `models/4-transformation.md` and `models/5-validation.md`

## Language packages implement

- `models/1-discovery.md` and `schemas/L1-discovery-result.schema.json`
- `reference/detection-rules.md` and `reference/framework-coverage.md`
- L4 apply — framework gate and the dependency, config, code, async, and logging recipes
- L5 runtime execution — `recipes/fresh-build-and-image.md`, plus the language deltas on the shared reference and
  validation-stack files
