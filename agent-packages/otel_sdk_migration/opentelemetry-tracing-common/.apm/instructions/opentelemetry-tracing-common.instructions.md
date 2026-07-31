---
description: Shared OpenTelemetry migration core for cross-language maturity/capability/validation logic, and the pipeline gates every language tracing skill obeys.
applyTo: "**/*"
---

# OpenTelemetry tracing (common)

When editing or extending cross-language tracing maturity logic, validation logic, or platform tracing contract for
OpenTelemetry migration, apply the `opentelemetry-tracing-common` skill.

## Pipeline gates (all language tracing skills)

These gates apply whenever a language tracing skill is active — `opentelemetry-tracing-java`,
`opentelemetry-tracing-go`, `opentelemetry-tracing-python`, or `opentelemetry-tracing-ts`.

Run **Phase 1 (L1–L3) read-only first**: post all three analysis briefs before
any L4 edits, builds, or runtime deploy. If the repository spans **multiple
language families**, ask the user **bulk vs single target** before L4 (the
`opentelemetry-tracing-common` Multi-language scope gate). Then Phase 2
(L4 + one post-L4 build + validation) if implementation is in scope.

After runtime deploy, run the **stand health gate** before Jaeger or end-to-end pass/fail
(`opentelemetry-tracing-common/recipes/stand-health-gate.md`). Do not leave validation
in a state where the SUT pod is not Ready or crash-looping.

Prefer Qubership platform conventions
(`opentelemetry-tracing-common/reference/platform-tracing-guide.md`, OTeC/Jaeger
export, `TRACING_*`) over generic OTel tutorials. Never auto-rename custom
attributes to semantic conventions without confirmation, and never close a tracing
task while sampling or propagation is unknown or unverified.
