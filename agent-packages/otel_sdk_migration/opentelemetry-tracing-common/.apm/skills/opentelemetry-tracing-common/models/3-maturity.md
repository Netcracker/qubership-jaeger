# Layer 3 — Maturity decision engine (shared)

**Goal:** map discovery + capability evidence to a **current** maturity level (1–5)
and a recommended next step. Do not re-scan the repository.

- **Input:** `discovery-result.json` and `capability-result.json`.
- **Output:** `maturity-result.json` → [`../schemas/L3-maturity-result.schema.json`](../schemas/L3-maturity-result.schema.json).
- **Match logic:** **Decision matrix** below only — walk rows top to bottom; first match wins.

## Input mapping (matrix columns)

| Matrix column     | Source                                                              |
|-------------------|---------------------------------------------------------------------|
| OTel API          | `discovery-result.dependencyProfile.hasOtelApi`                     |
| OTel SDK          | `discovery-result.dependencyProfile.hasOtelSdk`                     |
| Exporter          | `discovery-result.dependencyProfile.hasExporter`                    |
| Legacy active     | `discovery-result.dependencyProfile.hasLegacy`                      |
| Export capability | `capability-result.export.overall` → `PASS`, `PARTIAL`, or `FAILED` |

When `export.overall` is `UNKNOWN`, treat export capability as unknown for matrix
rows 5–6 and record the reason in `blockers` / `rationale` — do not guess `PASS` or `FAILED`.

## Decision matrix

| # | OTel API | OTel SDK | Exporter | Legacy active | Export capability | Level | Name | `recommendedAction` (JSON only) | Description (brief) | Recommended work (brief) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | any | yes | any | **yes** | any | **4** | Hybrid OTel | `remove-mixed-stack` | **Both** OpenTelemetry and a legacy tracer are active at the same time. | Remove the legacy stack and keep **one** OpenTelemetry instrumentation path. |
| 2 | no | no | any | **yes** | any | **2** | Legacy tracing | `migrate-to-otel` | The service relies on a **retired** tracing stack; OpenTelemetry is not the active path. | Migrate to OpenTelemetry — remove legacy libraries and wire OTel export and the platform tracing contract. |
| 3 | yes | no | any | no | any | **3** | Incomplete OTel | `complete-otel-stack` | OpenTelemetry is **partially** present but traces do not export end-to-end. | Complete the OTel stack — add or fix exporter, endpoint, sampler, and propagators until export works. |
| 4 | yes | yes | no | no | any | **3** | Incomplete OTel | `complete-otel-stack` | OpenTelemetry is **partially** present but traces do not export end-to-end. | Complete the OTel stack — add or fix exporter, endpoint, sampler, and propagators until export works. |
| 5 | yes | yes | yes | no | `FAILED` | **3** | Incomplete OTel | `complete-otel-stack` | OpenTelemetry is **partially** present but traces do not export end-to-end. | Complete the OTel stack — add or fix exporter, endpoint, sampler, and propagators until export works. |
| 6 | yes | yes | yes | no | `PASS`/`PARTIAL` | **5** | Working OTel | `no-migration-required` | OpenTelemetry SDK and exporter are wired; export works; no legacy tracer remains. | No full migration required — optional gap fixes, contract tuning, or validation only. |
| 7 | no | no | no | no | n/a | **1** | No tracing | `introduce-otel` | The service has no distributed tracing: no OTel SDK and no legacy tracer. | Introduce OpenTelemetry from scratch — dependencies, platform `TRACING_*` config, OTLP export, propagation, trace IDs in logs. |

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
     is `PARTIAL` or propagation is incomplete; `low` when required inputs are `UNKNOWN`.
4. Check the result carries every field listed in
   [`../schemas/L3-maturity-result.schema.json`](../schemas/L3-maturity-result.schema.json).

### Row 1 — the retired-exporter case

When the only "legacy" evidence is a retired **OTel-native** exporter (for example
`@opentelemetry/exporter-jaeger`, Python's `opentelemetry-exporter-jaeger*`) with no
separate tracer anywhere, the matrix still lands on row 1 (`hasLegacy=true`) — but
there is **one** tracer, not two. Describe the work as **swapping the exporter
package**, never as "remove the second tracing stack": that phrase is wrong when no
second stack exists.

## Propagation format

**The L3 brief is the only place the propagation format is raised with the user.**
Not the multi-language gate, not L4 — those consume the answer, they do not ask
for it again. Ask **once for the whole scope**, however many services it covers.

- **Level 1** — nothing configured, nothing defaulted: ask which format the fleet
  speaks, suggesting the contract default. L4 must not emit a propagation row
  before the answer arrives.
- **Levels 2–4** — a format is already configured: the migration preserves it.
  Raise it in the brief only when it conflicts with the contract default, and
  then as a question about peer compatibility, never as part of the migration.

What the user decides is the format and which one wins. Everything else — the
list order that expresses it, the constructor that produces it — the agent
derives. The rules, the framework defaults, and the winner-end table:
[`../reference/platform-tracing-guide.md`](../reference/platform-tracing-guide.md)
§Propagation.

Skip the target level and migration path for audit-only runs (no L4). Brief
template and timing: the language `SKILL.md` §3.1.
