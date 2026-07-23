# Layer 4 — Transformation (shared)

**Goal:** produce a reviewable `migration-plan.json` from Layer 1–3 artifacts,
then apply language-specific edits when implementation is in scope. Do not
re-run discovery or capability analysis.

- **Input:** `discovery-result.json`, `capability-result.json`,
  `maturity-result.json`.
- **Output:** `migration-plan.json` → [`../schemas/L4-migration-plan.schema.json`](../schemas/L4-migration-plan.schema.json).
- **Language-specific edits:** recipes and framework gates in each language
  package (Java: `opentelemetry-tracing-java` `models/4-transformation.md` Step 0).

## When to skip transformation edits

| `maturity-result.level` | Typical handling |
| --- | --- |
| **5** — Working OTel | Emit a **plan-only** document: `basedOnMaturityLevel: 5`, embedded `validationPlan`, optional gap fixes. No dependency/config/code/async sections unless the user asked for targeted fixes. |
| **1–4** with audit-only scope | Plan sections describe proposed changes; do **not** edit the target repository until the user opts into Phase 2. |
| Blockers in `maturity-result.blockers` | Record in plan `gaps`; do not apply edits that depend on missing evidence or blocked builds. |

Set `basedOnMaturityLevel` to `maturity-result.level` on every plan.

## Step 0 — Confirm scope (before framework gate)

When common **Multi-language scope gate** applies (two or more language
families or SUTs in scope), confirm user choice **bulk vs single target** before
any plan row or repository edit. If scope is unset, stop at plan-only output. See
common [`SKILL.md`](../SKILL.md) § Multi-language scope gate.

## Algorithm

1. **Confirm scope** — multi-language gate when applicable; record choice.
2. Read `maturity-result` — level, blockers, and recommended work (prose from L3).
3. Run the language **framework gate** when present (Java Step 0 / 0b) before
   any dependency or config row is emitted.
4. Fill plan sections **§4.1–§4.4** from language recipes when migration work
   is required (levels 1–4, or Level 5 with explicit fix scope).
5. Build **§4.5 `validationPlan`** — static and configuration tiers by default;
   runtime tier per common `models/5-validation.md` (opt-in).
6. Record unresolved items, skipped doc sync, and build blockers in `gaps`.
7. Validate against
   [`../schemas/L4-migration-plan.schema.json`](../schemas/L4-migration-plan.schema.json).
8. **Apply** (Phase 2 only) — edit the target repository, sync documentation (below),
   then run the language fresh-build recipe before runtime validation.

## Plan sections

### §4.1 `dependencyMigration`

`remove` / `add` / `upgrade` coordinates keyed on `discovery-result.dependencyProfile`.
Language recipes implement concrete moves.

### §4.2 `configMigration`

Array of `{ from, to, oneToOne, note? }` mappings toward the platform contract
([`../reference/platform-tracing-guide.md`](../reference/platform-tracing-guide.md)).
Flag non-1:1 mappings in `note`.

#### Propagation rows (mandatory handling)

Propagation is the one contract area a migration must **not** normalize on its
own. Follow §Propagation of the platform guide:

- **Format already configured** (L1 `propagation.inject` non-empty, or a known
  framework default) → carry the same inject format to the target stack. Emit
  the row as `oneToOne: true` even when the property path changes. Do **not**
  emit a row that switches the wire format.
- **Configured format conflicts with the contract default** → emit no switching
  row. Ask the user in chat (which peers speak which format, who else changes),
  and record the question and answer in plan `gaps`.
- **Nothing configured and nothing defaulted** (maturity Level 1) → ask the user
  to choose `B3` / `B3_MULTI` / `W3C` / a multi-format set before emitting the
  row, suggesting the contract default. Record the choice in `note`. Do not pick
  silently, and do not emit the row on an unanswered question — fall back to a
  plan-only document.
- Every propagation row must name the **concrete** target: property value, or
  constructor plus option where the format is set in code (Go
  `b3.New(b3.WithInjectEncoding(b3.B3MultipleHeader))`, not `b3.New()`), checked
  against the SDK source.
- **Derive** the composite order yourself — do not ask the user for it. They
  state which format wins; you map that to the framework's winner end (first on
  Spring Boot, last on Quarkus / Pure Java / Go). Record the resulting list and
  the reason in `note`, along with whether the surface is build-time or runtime.

### §4.3 `codeMigration`

- `mechanical` — deterministic API rewrites (may apply on confirmation). Examples
  of mechanical patterns (language recipes add framework-specific detail):
  - `span.tag(k, v)` → `span.setAttribute(k, v)`
  - `span.finish()` → `span.end()`
  - `buildSpan(name).start()` → `spanBuilder(name).startSpan()`
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

When Layer 4 edits are **applied** to the target repository (not plan-only),
update developer-facing docs in the same change set:

- Readme or installation guide — `TRACING_*` / OTel parameters and how to
  enable tracing.
- Deployment config — chart values, env mapping, or equivalent for the repository's
  install path.
- Non-obvious framework toggles — document in comments or install notes.

If the repository has no docs surface for deployment parameters, record
`documentation sync skipped — <reason>` in plan `gaps` instead of omitting
silently.

## User-facing summary (optional)

After `migration-plan.json`, a short **L4 Transformation summary** in chat helps
reviewers (prose, not raw JSON): framework path chosen, count of dependency/config
changes, async fixes, validation scope, and blockers. Format: each language root
skill (Java: `opentelemetry-tracing-java` `SKILL.md` Phase 2).
