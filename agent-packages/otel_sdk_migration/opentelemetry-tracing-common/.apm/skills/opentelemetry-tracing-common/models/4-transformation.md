# Layer 4 — Transformation (shared)

**Goal:** produce a reviewable `migration-plan.json` from Layer 1–3 artifacts, then apply
language-specific edits when implementation is in scope. Do not re-run discovery or capability analysis.

- **Input:** `discovery-result.json`, `capability-result.json`, `maturity-result.json`.
- **Output:** `migration-plan` — root fields in §Plan sections below, `validationPlan` in
  [`5-validation.md`](5-validation.md).
- **Language-specific edits:** recipes and the framework gate in each language
  package (`models/4-transformation.md` Step 0).

## When to skip transformation edits

| `maturity-result.level`                | Typical handling                                                                                                                                                                            |
|----------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **5** — Working OTel                   | Emit a **plan-only** document: `basedOnMaturityLevel: 5`, embedded `validationPlan`, optional gap fixes. No dependency/config/code/async sections unless the user asked for targeted fixes. |
| **1–4** with audit-only scope          | Stop after the L3 brief. It already names the recommended work, so do not produce a plan document unless the user asks for one — and never edit the target repository.                      |
| Blockers in `maturity-result.blockers` | Record in plan `gaps`; do not apply edits that depend on missing evidence or blocked builds.                                                                                                |

## Algorithm

1. **Confirm scope** — when two or more language families or SUTs are in scope,
   settle **bulk vs single target** before any plan row or repository edit, and
   record the choice: common [`SKILL.md`](../SKILL.md) §Multi-language scope gate.
2. Read `maturity-result` — level, blockers, and recommended work (prose from L3).
3. Run the language **framework gate** (`models/4-transformation.md` Step 0 and
   Step 0b) before any dependency or config row is emitted.
4. Fill plan sections **§4.1–§4.4** from language recipes when migration work
   is required (levels 1–4, or Level 5 with explicit fix scope).
5. Build **§4.5 `validationPlan`** — static and configuration tiers by default;
   runtime tier per common `models/5-validation.md` (opt-in).
6. Record unresolved items, skipped doc sync, and build blockers in `gaps`.
7. Check the plan carries every field in §Plan sections, and the `validationPlan` structure from
   [`5-validation.md`](5-validation.md).
8. **Apply** (Phase 2 only) — edit the target repository, sync documentation (below),
   then run the language fresh-build recipe before runtime validation.

## Plan sections

The plan is one object. Every field below is expected; an unresolved one goes in `gaps` rather than being dropped.

| Field                   | Shape                                            | Section                                             |
| ----------------------- | ------------------------------------------------ | --------------------------------------------------- |
| `basedOnMaturityLevel`  | integer 1–5, copied from `maturity-result.level` | every plan, including plan-only                     |
| `dependencyMigration`   | `{ remove[], add[], upgrade[] }` of coordinates  | §4.1                                                |
| `configMigration`       | array of `{ from, to, oneToOne, note? }`         | §4.2                                                |
| `codeMigration`         | `{ mechanical[], semantic[] }`                   | §4.3                                                |
| `asyncContextMigration` | array of `{ boundary, file?, line?, fix }`       | §4.4                                                |
| `validationPlan`        | `{ static[], configuration[], runtime }`         | §4.5, shape in [`5-validation.md`](5-validation.md) |
| `gaps`                  | array of prose strings with evidence             | throughout                                          |

### §4.1 `dependencyMigration`

`remove` / `add` / `upgrade` coordinates keyed on `discovery-result.dependencyProfile`.
Language recipes implement concrete moves.

### §4.2 `configMigration`

Array of `{ from, to, oneToOne, note? }` mappings toward the platform contract
([`../reference/platform-tracing-guide.md`](../reference/platform-tracing-guide.md)).
Flag non-1:1 mappings in `note`.

#### Propagation rows (mandatory handling)

L4 encodes the format decided in the L3 brief
([`3-maturity.md`](3-maturity.md) §Propagation format); it never re-asks, and it
never normalizes the wire format on its own.

- Carry the decided inject format to the target stack. Emit the row as
  `oneToOne: true` even when the property path changes, and never emit a row that
  switches the wire format.
- Name the **concrete** target: the property value, or the constructor plus option
  where the format is set in code (Go
  `b3.New(b3.WithInjectEncoding(b3.B3MultipleHeader))`, not `b3.New()`), checked
  against the SDK source of the version the repository depends on.
- Record in `note`: the resulting list, why that order, and whether the surface is
  build-time or runtime.

### §4.3 `codeMigration`

- `mechanical` — deterministic API rewrites (may apply on confirmation); the
  concrete rewrite tables live in the language `recipes/code-migration.md`.
- `semantic` — attribute renames, business-key mappings, and OpenTelemetry
  semantic convention proposals only; **never auto-apply**. List candidates in
  `codeMigration.semantic` and ask for confirmation. Custom keys require explicit
  user approval before any rename.

### §4.4 `asyncContextMigration`

Array of `{ boundary, file?, line?, fix }` for each context-loss candidate from
`discovery-result.asyncBoundaries` that remains `FAILED` in capability.

### §4.5 `validationPlan` (embedded Layer 5)

Required on every plan. Structure and tiers: [`models/5-validation.md`](5-validation.md).
Runtime checks are opt-in; static + configuration run without a deploy.

There is **no** `documentationMigration` field in the schema. Documentation
updates are an **apply-time** obligation (below), not a JSON section.

## Documentation sync (on apply)

When Layer 4 edits are **applied** to the target repository (not plan-only), rewrite the affected tracing
documentation in the same change set. **Rewrite the section, do not patch the lines that changed.** After a migration
the surrounding prose describes a stack that no longer exists — a readme that still explains Sleuth while the table
below it lists OTLP variables is worse than one that was never touched.

In scope for the rewrite:

- the tracing section of the readme or installation guide — what the service exports, where, how to enable it, and the
  full `TRACING_*` / OTel parameter set with defaults;
- deployment config docs — chart values, env mapping, or the equivalent for the repository's install path;
- non-obvious framework toggles — in comments or install notes, especially build-time ones;
- anything naming the retired stack: remove the legacy tracer from prose, diagrams, and examples rather than leaving it
  beside its replacement.

Out of scope: documentation about parts of the service the migration did not touch. Rewrite the tracing section, not
the document.

If the repository has no docs surface for deployment parameters, record `documentation sync skipped — <reason>` in plan
`gaps` instead of omitting silently.

## User-facing summary (optional)

After the plan, a short prose summary in chat helps reviewers: framework path
chosen, counts of dependency, config, and async changes, validation scope, and
blockers. Never the raw JSON.
