# User-facing layer briefs (L1–L3, mandatory)

After each analysis layer completes, post a short **thesis-style summary in the agent chat** before moving to the next
layer. Someone who finishes a migration must see the current telemetry picture without opening JSON. Keep each brief to
5–10 bullets and cite evidence paths where they are not obvious.

Briefs do **not** replace the artifacts, and the artifacts do not replace the briefs. Do not skip the briefs when
implementing changes: they are the handoff record for reviewers and for the user returning to close the migration.

Two rules apply to all three briefs:

- **Plain language, never schema tokens.** No `PASS`/`PARTIAL`/`FAILED`/`UNKNOWN`, no `platformContract` facet keys, no
  `recommendedAction` slugs such as `introduce-otel`. Those belong in the artifact only.
- **Say where a value came from.** "Not configured" is not the same as "not propagating" — a framework default is still
  an effective value, and the brief must say which of the two it is.

Language packages add their own fields to the L1 brief (framework stack, module system, instrumentation mechanism)
in `SKILL.md` §3.1.

## L1 — Discovery brief

- framework and service name;
- dependency buckets — OTel API / SDK / exporter present, legacy tracer present, key artifacts;
- export and sampling configuration, or "none configured";
- **propagation, as two directions**, in plain words, naming the source of each: for example "accepts W3C, B3 and
  B3-multi inbound; sends **W3C only** outbound — both are framework defaults, nothing is set in config". Where a value
  is a framework default rather than a written key, say so. Add "(changing this needs a rebuild)" where the surface is
  build-time;
- instrumentation mode — auto, manual, mixed, or none;
- async-boundary hotspots (Kafka, executors, reactive, workers) or "none found";
- **platform gaps**, only when they exist: plain-language issues with file paths, for example "logs lack trace IDs" or
  "export still points at Zipkin, not OTLP to the collector".

## L2 — Capability brief

- propagation verdict per component (HTTP, Kafka, async) in plain language, for example "Kafka loses context on async
  handoff";
- **inbound and outbound compatibility, stated separately.** Whether what the service *sends* matches what its peers
  read is a different answer from whether it *understands* what arrives. Call out the asymmetric case explicitly,
  because no end-to-end test will show it: "incoming traces are picked up fine, but outgoing calls emit a format that
  B3-only peers ignore";
- span quality — lifecycle, attributes, errors — at a high level;
- export path — exporter, endpoint, protocol, target — in prose;
- platform-contract compliance in human terms: service naming, sampling, propagation, log correlation, export shape.

## L3 — Maturity brief

Decision matrix and level wording: [`../models/3-maturity.md`](../models/3-maturity.md).

- **Current level** — number, name, and one sentence on what it means for this repository.
- **Recommended work** — what to do next, in prose.
- **Target level** (only when L4 is planned) — where the service should land, usually Level 5.
- **Migration path** (mandatory when L4 is planned) — one line, `Migration path: Level <current> → Level <target>`.
  Never the shorthand "1→2": Level 2 means legacy tracing **today**, not step two of a plan.
- One-line rationale with a file or config cited.
- Blockers or gaps that affect the transformation plan.
- The **propagation-format question**, when the format is unconfigured or conflicts with the contract default — this
  brief is the only place it is raised ([`../models/3-maturity.md`](../models/3-maturity.md) §Propagation format).

Example shape:

```markdown
### L3 Maturity — order-service
- **Current level:** Level 2 — Legacy tracing — Spring Cloud Sleuth is on the classpath; no working OTel export.
- **Recommended work:** Migrate to OpenTelemetry: remove Sleuth, add the Micrometer OTel bridge and OTLP export.
- **Target level:** Level 5 — Working OTel — single OTel stack, traces reach the collector, legacy libs removed.
- **Migration path:** Level 2 → Level 5
- **Rationale:** `pom.xml` declares Sleuth; no working OTLP export path is configured.
- **Blockers:** none
```
