# opentelemetry-tracing-umbrella

Shared tracing core package for all language-specific tracing skills.

## Pipeline

Layers L2–L5 shared logic lives here; L1 and runtime execution live in each
language package. See
[`.apm/skills/opentelemetry-tracing-umbrella/SKILL.md`](.apm/skills/opentelemetry-tracing-umbrella/SKILL.md)
for the full ownership split and artifact chain.

## Contents

- **Models:** `models/2-capability.md`, `models/3-maturity.md`,
  `models/4-transformation.md`, `models/5-validation.md`
- **Schemas:** `schemas/L2-capability-result.schema.json`,
  `schemas/L3-maturity-result.schema.json`, `schemas/L4-migration-plan.schema.json`
- **Reference:** `reference/` — platform contract (`platform-tracing-guide.md` via umbrella)

## Language packages implement

- `models/1-discovery.md` and `schemas/L1-discovery-result.schema.json`
- `reference/detection-rules.md`
- L4 apply (framework gate, recipes) and L5 runtime execution (build, deploy, validation recipes)
