# Open questions for the tracing skills (cross-language)

Working list of unresolved / under-specified decisions that are **shared across
all language packages** (Java, Go, Python, TypeScript). Two kinds of question live
here:

- **general** — the decision belongs entirely to the platform contract / shared
  logic (common) and applies identically to every language;
- **hybrid** — the concept is shared but the concrete realization is refined per
  language package; here the question is posed **language-agnostically**.

Language-specific questions are **not** in this list — each is decided inside its
own package. (For Python they are already closed by applying the recommended
option directly in the skill.)

**How to read this:**

- Every question carries answer options (a/b/c/…).
- The option marked **✅** is the AI recommendation (a proposal, not a verdict —
  accept it, reject it, or replace it with your own).
- A letter (A, B, C…) is an area (grouping). A letter+number (A1, C2…) is a
  concrete question — the unit of discussion.
- An answer to a general/hybrid question should land in the common contract /
  shared layers so it propagates to every language.
- The "Decision" line is filled in as decisions are made.

24 questions total (A1–K2).

---

## A. Instrumentation mechanism (auto / manual)

### A1 — Policy for choosing the target mechanism from the input state

(auto = zero-code / launcher / agent; manual = explicit instrumentation + hand-written spans.)

- (a) Preserve existing; greenfield → **explicit (manual) instrumentation** (control over resource, provider, exporter lifecycle) ✅
- (b) Preserve existing; greenfield → **auto / zero-code** (cheapest start)
- (c) Always normalize everything to explicit instrumentation
- (d) Always prefer auto

**Decision:**

### A2 — What exactly does the "single mechanism" rule forbid?

- (a) Only double-instrumenting *the same library*; auto/framework instrumentation + your own business spans are allowed ✅
- (b) Any `mixed` is forbidden — strictly one mechanism per service
- (c) Drop the ban, only warn

**Decision:**

---

## B. Framework / role detection

### B1 — "server span on a business endpoint" assertion for non-web services

A worker/CLI/consumer has no inbound request → no server span, yet L5 requires one.

- (a) Make the assertion conditional: for non-web, a root span on the unit of work (task / processed message) ✅
- (b) Keep the HTTP assertion, mark non-web as `n/a`
- (c) Always require an HTTP endpoint (force a web wrapper)

**Decision:**

### B2 — A service combines several roles (web + async worker, etc.)

A single framework value cannot describe a service that both serves requests and runs as a worker.

- (a) Split into 2 independent axes: request-serving framework + async runtime ✅
- (b) Single value, the second role goes into `gaps`
- (c) A separate `discovery-result` per role

**Decision:**

---

## C. Propagation

### C1 — Greenfield: ask for the format or default to the contract one?

- (a) Contract default (`b3multi`) with no question; ask only when peer incompatibility is known ✅
- (b) Always ask for the format
- (c) Default to W3C `tracecontext`, contract one on request

**Decision:**

### C2 — Format conflicts with the contract, user unavailable (bulk)

- (a) Do not change the format, record in `gaps`, contract status `unknown`, do not fail ✅
- (b) Force the contract format
- (c) Halt the migration until answered

**Decision:**

### C3 — Brownfield: how to determine propagation-order priority ("who wins")

- (a) From the existing order in code/config, not from a guess ✅
- (b) Always normalize to the contract
- (c) Ask the user which end wins

**Decision:**

---

## D. Sampling

### D1 — The platform's rate-limiting sampler has no native OTel equivalent

- (a) Approximate with parent-based ratio + record the mismatch in `gaps` (honest) ✅
- (b) Pull in a third-party rate-limiting sampler
- (c) Ignore rate-limiting, silently force a probabilistic ratio

**Decision:**

### D2 — Legacy `SAMPLER_PARAM` → ratio

- (a) Convert only the probabilistic branch; const/rate-limiting → `gaps` ✅
- (b) Convert everything to a ratio mechanically
- (c) Do not convert, leave it to manual tuning

**Decision:**

### D3 — `consistentAcrossServices` on a single repository

- (a) Always `unknown` + a "fleet-level property" note ✅
- (b) Derive `yes/no` from local config
- (c) Drop the field from the schema for single-service

**Decision:**

---

## E. Export

### E1 — gRPC vs HTTP

- (a) Default `http/protobuf` always; gRPC only if already configured in the service ✅
- (b) Ask the user every time
- (c) Suggest gRPC for high-throughput services

**Decision:**

### E2 — Choosing the proxy alias (`nc-diagnostic-agent` vs `open-telemetry-collector`)

- (a) Default the first; if the second is found in Helm/cluster, use it; otherwise `gaps` ✅
- (b) Always `nc-diagnostic-agent`
- (c) Always ask for the alias

**Decision:**

### E3 — What counts as an export pass in L5

- (a) Span found in the backend query API (actually delivered) ✅
- (b) Span creation in-process is enough
- (c) Absence of export errors in logs is enough

**Decision:**

---

## F. Async / context

### F1 — Scope of the async-boundary fix

- (a) Fix all FAILED, but mark boundaries not covered by traffic `unverified`, not `pass` ✅
- (b) Fix only boundaries on the test-traffic path
- (c) Fix all and call it `pass` without a runtime check

**Decision:**

### F2 — Auto/agent instrumentation does not cover manual thread pools / subprocess

Context is lost across manual concurrency regardless of the chosen mechanism.

- (a) Document explicitly: these boundaries always need a code-level fix regardless of mechanism ✅
- (b) Rely on the mechanism to cover them
- (c) Forbid manual concurrency in auto services

**Decision:**

---

## G. Logging correlation

### G1 — Service already writes a trace ID under a different field name vs the contract one

- (a) Do not break silently — offer a rename as a proposal (like semantic renames) ✅
- (b) Auto-rename to the contract name
- (c) Accept the existing name as compatible, leave it

**Decision:**

---

## H. Versioning / dependencies

### H1 — Greenfield: "defer versions from the manifest" does not apply (there is no manifest)

- (a) Do not pin, install a coherent compatible set, record the resolved versions in the plan ✅
- (b) Pin the latest stable explicitly in the skill
- (c) Pin to the service's minimum supported runtime version

**Decision:**

---

## I. Scope / phase gates

### I1 — What triggers a semantic-rename proposal?

- (a) Only mappings to stable semconv (`http.route`, `db.system`…); do not touch custom business keys ✅
- (b) Any non-semconv attribute → proposal
- (c) Propose nothing, only mechanical rewrites

**Decision:**

### I2 — Scope of docs sync

- (a) Only install/deploy docs + Helm values where env/deps changed ✅
- (b) Full rewrite of the tracing section
- (c) Do not touch docs, write a changelog note

**Decision:**

### I3 — Multi-language default when the user is silent

- (a) Default single-target (current service); bulk only on explicit request ✅
- (b) Default bulk (all services)
- (c) Always stop and ask

**Decision:**

---

## J. Contradictions between this list and the shipped skill

These are not new design questions: the skill already implements one answer while
this list recommends another. Until each is decided, the skill text is the acting
behavior and the ✅ below is only a proposal to change it.

### J1 — Greenfield propagation: ask, or apply the contract default silently?

Duplicate of **C1**, recorded here because the conflict is live. The skill
(`models/3-maturity.md` §Propagation format, `platform-tracing-guide.md`
§Propagation rule 3) **asks the user** and forbids L4 from emitting a propagation
row before the answer arrives. C1 ✅ recommends the opposite: apply `b3multi`
without a question.

- (a) Keep the skill as it is — ask once per scope in the L3 brief; the format is a
  fleet property and a silent choice is unrecoverable across peers ✅
- (b) Apply the C1 ✅ instead: contract default silently, ask only on known peer
  incompatibility, and rewrite both skill sections
- (c) Ask only when the scope contains more than one service

**Decision:**

### J2 — Multi-language scope when the user is silent

Duplicate of **I3**, same situation. The skill (common `SKILL.md` §Multi-language
scope gate) **stops and asks**, then falls back to a plan-only document with
`runtime.status: manual` if unanswered. I3 ✅ recommends defaulting to
single-target instead.

- (a) Keep the skill as it is — ask, and degrade to plan-only when unanswered; no
  repository edits happen on an unanswered question either way ✅
- (b) Apply the I3 ✅: default to the current service and rewrite the gate
- (c) Default to single-target for edits but still report the other targets found

**Decision:**

### J3 — Best-effort frameworks and the `service.framework` enum

Each language package documents best-effort frameworks with concrete
instrumentation, but the `service.framework` enum can only record `unknown` for
them, so the chosen instrumentation survives only in prose. Go additionally has
`gin` and `echo` in its enum, which makes "best-effort" mean two different things
across packages.

- (a) Enum stays first-class-only; best-effort records as `unknown` plus the
  identified framework and chosen instrumentation in `gaps` — uniform across
  packages ✅
- (b) Add every best-effort framework to each enum
- (c) Add a separate `frameworkDetail` string field alongside the enum

**Decision:**

### J4 — Does an audit-only run still owe the user the L4/L5 sections?

`models/4-transformation.md` says an audit-only run describes proposed changes
without editing, while the phase gate says to stop after the L3 brief. Both are
defensible, but they describe different deliverables for the same request.

- (a) Stop after L3, and produce the plan only when the user asks for it — the L3
  brief already names the recommended work ✅
- (b) Always produce the full plan document, edits excluded
- (c) Ask the user which deliverable they want after the L3 brief

**Decision:**

---

## K. Artifacts and evidence

### K1 — Do the five artifacts ever become files?

The skill now states they are in-session data and must not be written to disk
(common `SKILL.md` §Where the artifacts live). That closes the ambiguity, but not
the question of whether a user who *asks* for files gets a documented location.

- (a) On explicit request only, and outside the target repository (scratch
  directory), so Phase 1 stays read-only ✅
- (b) A documented path inside the repository, gitignored
- (c) Never — always chat only

**Decision:**

### K2 — Schemas are never executed

Nothing in CI validates an artifact against `schemas/`, so the schemas are a
shared vocabulary the model reads rather than a contract anything enforces.

- (a) Keep them as documentation of the shape, and say so in the schema
  description so no one expects validation ✅
- (b) Add a CI job that validates sample artifacts against the schemas
- (c) Drop the schemas and describe the shape in the models only

**Decision:**
