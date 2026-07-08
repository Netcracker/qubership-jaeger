# Layer 3 — Maturity decision engine (shared)

**Goal:** map discovery + capability evidence to a **current** maturity level (1–5)
and a recommended next step. Do not re-scan the repository.

- **Input:** `discovery-result.json` and `capability-result.json`.
- **Output:** `maturity-result.json` → [`../schemas/L3-maturity-result.schema.json`](../schemas/L3-maturity-result.schema.json).
- **Match logic:** **Decision matrix** below only — walk rows top to bottom; first
  match wins.

## Input mapping (matrix columns)

| Matrix column | Source |
| --- | --- |
| OTel API | `discovery-result.dependencyProfile.hasOtelApi` |
| OTel SDK | `discovery-result.dependencyProfile.hasOtelSdk` |
| Exporter | `discovery-result.dependencyProfile.hasExporter` |
| Legacy active | `discovery-result.dependencyProfile.hasLegacy` |
| Export capability | `capability-result.export.overall` → `PASS`, `PARTIAL`, or `FAILED` |

When `export.overall` is `UNKNOWN`, treat export capability as unknown for matrix
rows 5–6 and record the reason in `blockers` / `rationale` — do not guess
`PASS` or `FAILED`.

## Decision matrix

Walk rows **1 → 7**; stop at the first match. Use matched `level`, `label`, and
`recommendedAction` in `maturity-result.json`. Use **Recommended work** in
user-facing L3 briefs — not the `recommendedAction` slug.

| # | OTel API | OTel SDK | Exporter | Legacy active | Export capability | Level | Name | `recommendedAction` (JSON only) | Description (brief) | Recommended work (brief) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | any | yes | any | **yes** | any | **4** | Hybrid OTel | `remove-mixed-stack` | **Both** OpenTelemetry and a legacy tracer are active at the same time. | Remove the legacy stack and keep **one** OpenTelemetry instrumentation path. |
| 2 | no | no | any | **yes** | any | **2** | Legacy tracing | `migrate-to-otel` | The service relies on a **retired** tracing stack; OpenTelemetry is not the active path. | Migrate to OpenTelemetry — remove legacy libraries and wire OTel export and the platform tracing contract. |
| 3 | yes | no | any | no | any | **3** | Incomplete OTel | `complete-otel-stack` | OpenTelemetry is **partially** present but traces do not export end-to-end. | Complete the OTel stack — add or fix exporter, endpoint, sampler, and propagators until export works. |
| 4 | yes | yes | no | no | any | **3** | Incomplete OTel | `complete-otel-stack` | OpenTelemetry is **partially** present but traces do not export end-to-end. | Complete the OTel stack — add or fix exporter, endpoint, sampler, and propagators until export works. |
| 5 | yes | yes | yes | no | `FAILED` | **3** | Incomplete OTel | `complete-otel-stack` | OpenTelemetry is **partially** present but traces do not export end-to-end. | Complete the OTel stack — add or fix exporter, endpoint, sampler, and propagators until export works. |
| 6 | yes | yes | yes | no | `PASS`/`PARTIAL` | **5** | Working OTel | `no-migration-required` | OpenTelemetry SDK and exporter are wired; export works; no legacy tracer remains. | No full migration required — optional gap fixes, contract tuning, or validation only. |
| 7 | no | no | no | no | n/a | **1** | No tracing | `introduce-otel` | The service has no distributed tracing: no OTel SDK and no legacy tracer. | Introduce OpenTelemetry from scratch — dependencies, platform `TRACING_*` config, OTLP export, propagation, trace IDs in logs. |

Do **not** invent levels or match from level names alone — use this table only.

## Algorithm

1. Read the input mapping table from Layer 1 and Layer 2 artifacts.
2. Walk the **Decision matrix** rows **1 → 7**; stop at the first matching row.
3. Emit `maturity-result.json`:
   - `level`, `label`, `recommendedAction` — from the matched row (schema enums).
   - `rationale` — cite the matrix row number and the discovery/capability
     fields that satisfied it (file paths or JSON field names).
   - `blockers` — carry forward unresolved `gaps`, export `FAILED`, hybrid
     legacy+OTel, or any facet that blocks L4.
   - `confidence` — `high` when all matrix inputs are known; `medium` when export
     is `PARTIAL` or propagation is incomplete; `low` when required inputs are
     `UNKNOWN`.
4. Validate against
   [`../schemas/L3-maturity-result.schema.json`](../schemas/L3-maturity-result.schema.json).

### Examples (for briefs — plain language)

- **Level 1:** A new service with no tracing libraries in `pom.xml` and no trace
  export configured → tracing must be **introduced from zero**. This is not
  “level 2” and not “step 1→2” — Level 2 means **legacy** tracing only.
- **Level 2:** Spring Boot still on **Spring Cloud Sleuth** → migrate from legacy
  tracing to OpenTelemetry.
- **Level 3:** `opentelemetry-api` in dependencies but no OTLP exporter or export
  fails → **finish** wiring the OTel stack.
- **Level 4:** Brave and OTel Java agent both present → **remove** the mixed stack.
- **Level 5:** Quarkus with `quarkus-opentelemetry` and OTLP export working, no
  Sleuth/Jaeger client → tracing is **already in good shape**.

## Current level vs migration goal (user brief)

The matrix produces one verdict: the **current** state. In chat, describe it
with **level + name + one sentence** from the **Description** column.

**Level 2 = legacy tracing today**, not “after we add OpenTelemetry”. Never write
“1→2” as a migration step.

When L4 implementation is planned, add a **target level** in the L3 brief only
(not a second matrix lookup, not a schema field):

- **Current level** — what the service is today (level, name, short description).
- **Target level** — where L4 should land if it succeeds. For levels 1–4, the
  target is usually **Level 5 — Working OTel** (OTLP export to the platform
  collector, platform contract met, no legacy libraries).
- **Migration path** (mandatory in chat when L4 is planned) — one line:
  **`Migration path: Level <current> → Level <target>`** (e.g.
  `Migration path: Level 2 → Level 5`). This is the planned transformation arc,
  not shorthand like “1→2” (Level 2 means **legacy tracing today**, not “step
  two of a plan”).

Skip the target level and migration path for audit-only runs (no L4). Brief
template and timing: each language root skill (Java: `opentelemetry-tracing-java`
`SKILL.md` §3.1).
