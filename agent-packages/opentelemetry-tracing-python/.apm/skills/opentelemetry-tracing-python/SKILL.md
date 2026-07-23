---
name: opentelemetry-tracing-python
description: Audits distributed tracing in unknown Python services (FastAPI/ASGI, Django and Flask/WSGI, pure OTel SDK), scores maturity (levels 1-5), and produces OpenTelemetry migration and validation plans against the Qubership platform tracing contract. Use when the repository has no tracing, legacy tracing (Zipkin/py_zipkin/OpenTracing/Jaeger client), hybrid or incomplete OTel, broken Celery/Kafka/thread-pool/executor context propagation, failed OTLP export, or work touching TRACING_* variables, sampling, B3/b3multi/W3C propagation, traceId/spanId log correlation, requirements.txt/pyproject.toml tracing dependencies, or Helm tracing values — including when the user only mentions tracing, spans, Jaeger, OpenTelemetry, or broken/missing traces without naming this skill. Prefer over generic OTel advice for any Python tracing change to code, config, Helm, or dependencies. Do NOT use for Java/Go/JS/TS services.
---

# OpenTelemetry tracing audit & migration engine (Python)

This skill is an analysis pipeline. It takes an unknown Python repository as input
and produces five machine-readable artifacts: discovery profile, capability
assessment, maturity verdict, migration plan, and validation plan.

Read umbrella platform contract first:
[`platform-tracing-guide.md`](../opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md)
— it is the binding source for `TRACING_*` parameters, OTLP export shape,
B3/B3Multi propagation, sampling, service naming, endpoint filtering, and log
correlation. Auto-instrumentation and framework middleware are allowed only when
they preserve that contract.

## 1. When to apply

Use for:

- enabling or auditing distributed tracing in Python services;
- migrating legacy stacks (Zipkin/py_zipkin/OpenTracing/Jaeger client) to OTel;
- fixing incomplete OTel (API only, missing exporter, broken OTLP endpoint);
- fixing context propagation loss across Celery/Kafka/thread pools/executors/subprocesses;
- work touching `TRACING_*`, OTLP, sampling, propagators, or trace-log correlation.

Do not use for Java/Go/JS/TS services.

## 2. Pipeline overview

```text
repository
   │
   ▼
[L1] Discovery   ──► discovery-result.json
   │
   ▼
[L2] Capability  ──► capability-result.json
   │
   ▼
[L3] Maturity    ──► maturity-result.json
   │
   ▼
[L4] Transformation ─► migration-plan.json
   │
   ▼
[L5] Validation  ──► validationPlan (embedded in migration-plan)
```

Layer ownership:

- L1: this package (`models/1-discovery.md`, Python rules and recipes)
- L2-L5: umbrella shared logic with Python runtime execution details

## 3. Execution order

### 3.0 Mandatory phase split

**Phase 1 (read-only):** L1-L3 and three user briefs.

During Phase 1, do not:

- edit source/config/Helm/docs;
- run build/image/runtime deploy;
- apply L4 recipes.

**Phase 2 (implementation):** L4 + one post-L4 build + L5 validation.

**Multi-language repository:** if the repository contains services in **other language
families** besides Python, run the umbrella
[Multi-language scope gate](../opentelemetry-tracing-umbrella/SKILL.md)
— ask the user **bulk vs single target** before any L4 edit.

### 3.1 User-facing briefs (mandatory)

After each L1, L2, L3 artifact, post a short brief:

- L1: framework stack (`service.framework`), dependency buckets, export/sampling,
  instrumentation mode, async hotspots, platform gaps. State **propagation as two
  directions** in plain words — what is accepted inbound vs what is sent outbound
  — and name the source of each (explicit config, or an SDK/instrumentation
  default). "Not configured" is not "not propagating".
- L2: propagation verdict, span quality, export path, platform compliance. Report
  inbound and outbound compatibility **separately** — a service can read incoming
  traces fine and still emit a format its peers ignore, which no end-to-end test
  will show.
- L3: current level, recommended work in prose, target level (if L4 planned),
  **migration path** (`Migration path: Level N → Level M` when L4 planned),
  blockers.

### 3.2 Post-L4 build rule (once)

When L4 edits exist:

1. run fresh build and image once (see `recipes/fresh-build-and-image.md`);
2. do not rebuild again for runtime if L4 files are unchanged;
3. never validate runtime on stale image built before L4.

### 3.3 Runtime opt-in

After successful post-L4 build, ask user before runtime deploy.
If user declines or environment is unknown, set runtime status to `manual`.

### 3.4 Runtime order

Umbrella §5.3 — execute in order:

```text
deploy -> stand health -> log error triage -> business traffic -> tracing assertions -> pass/fail -> validation cleanup (on pass)
```

Recipes (umbrella):

- [`recipes/stand-health-gate.md`](../opentelemetry-tracing-umbrella/recipes/stand-health-gate.md)
- [`recipes/log-error-triage.md`](../opentelemetry-tracing-umbrella/recipes/log-error-triage.md)

Never do Jaeger-first pass/fail.

### 3.5 Post-validation cleanup (mandatory after runtime `pass`)

When `validationPlan.runtime.status` is `pass`, run
[`recipes/validation-cleanup.md`](../opentelemetry-tracing-umbrella/recipes/validation-cleanup.md). See umbrella
[`models/5-validation.md`](../opentelemetry-tracing-umbrella/models/5-validation.md)
§5.4.

## 4. Output contract

Produce:

- `discovery-result.json` (Python schema in this package)
- `capability-result.json` (umbrella schema redirect)
- `maturity-result.json` (umbrella schema redirect)
- `migration-plan.json` (umbrella schema redirect; includes `validationPlan`)

## 5. Non-negotiable rules

| Rule                                  | Reason                                                                                                                                               |
|---------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------|
| Platform contract is binding          | Must enforce `TRACING_*`, OTLP `http/protobuf`, `b3multi`, `parentbased_traceidratio`, `${name}-${namespace}`, endpoint filtering, trace IDs in logs |
| Evidence-first                        | Every claim cites file/path/env key                                                                                                                  |
| No semantic auto-rename               | Semantic-convention renames are proposals, not automatic edits                                                                                       |
| One tracing stack                     | Final state cannot keep legacy Zipkin/OpenTracing/Jaeger as active stack                                                                             |
| One instrumentation mechanism         | Do not run the `opentelemetry-instrument` auto-launcher and manual `.instrument()` for the same library — double instrumentation duplicates spans    |
| Sampling & propagation mandatory      | Validation fails if unknown or unverified                                                                                                            |
| Defer versions                        | Read versions from `requirements.txt`/`pyproject.toml`, never hardcode versions in skill text                                                        |
| Sync docs on L4                       | If L4 changes config/env/deps, update service docs in the same pass                                                                                  |
| Fresh post-L4 build                   | Runtime pass requires post-L4 dependency reinstall + image provenance                                                                                |
| End-to-end only when stand is healthy | Runtime `pass` needs stand health + log triage before Jaeger (§3.4; umbrella L5)                                                                     |
| No Jaeger-first pass                  | Jaeger spans while SUT crash-loops or not Ready are not end-to-end pass — fix the stand first                                                        |

## 6. File index

- Models: [`models/`](models/) — L4 framework/mechanism gate in [`models/4-transformation.md`](models/4-transformation.md); L5 Python delta in [`models/5-validation.md`](models/5-validation.md)
- Schemas: [`schemas/`](schemas/)
- Detection signatures: [`reference/detection-rules.md`](reference/detection-rules.md)
- Build blockers: [`reference/build-preconditions.md`](reference/build-preconditions.md)
- Runtime install discovery: [`reference/service-installation-discovery.md`](reference/service-installation-discovery.md)
- Recipes: [`recipes/`](recipes/) — L4 apply + `fresh-build-and-image`, `validation-stack`
- Shared L5 runtime (umbrella): [`recipes/stand-health-gate.md`](../opentelemetry-tracing-umbrella/recipes/stand-health-gate.md), [`recipes/log-error-triage.md`](../opentelemetry-tracing-umbrella/recipes/log-error-triage.md), [`recipes/validation-cleanup.md`](../opentelemetry-tracing-umbrella/recipes/validation-cleanup.md)
