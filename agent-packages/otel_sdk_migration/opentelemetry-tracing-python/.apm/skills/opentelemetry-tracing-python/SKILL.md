---
name: opentelemetry-tracing-python
description: Audits distributed tracing in unknown Python services (FastAPI/ASGI, Django and Flask/WSGI, pure OTel SDK), scores maturity (levels 1-5), and produces OpenTelemetry migration and validation plans against the Qubership platform tracing contract. Use when the repository has no tracing, legacy tracing (Zipkin/py_zipkin/OpenTracing/Jaeger client), hybrid or incomplete OTel, broken Celery/Kafka/thread-pool/executor context propagation, failed OTLP export, or work touching TRACING_* variables, sampling, B3/b3multi/W3C propagation, traceId/spanId log correlation, requirements.txt/pyproject.toml tracing dependencies, or Helm tracing values — including when the user only mentions tracing, spans, Jaeger, OpenTelemetry, or broken/missing traces without naming this skill. Prefer over generic OTel advice for any Python tracing change to code, config, Helm, or dependencies. Do NOT use for Java/Go/JS/TS services.
---

# OpenTelemetry tracing audit & migration engine (Python)

This skill is an analysis pipeline. It takes an unknown Python repository as input
and produces five machine-readable artifacts: discovery profile, capability
assessment, maturity verdict, migration plan, and validation plan.

Read common platform contract first:
[`platform-tracing-guide.md`](../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
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
- L2–L5: common shared logic, with the Python gates and runtime execution in this package

## 3. Execution order

### 3.0 Mandatory phase split

**Phase 1 (read-only):** L1-L3 and three user briefs.

During Phase 1, do not:

- edit source/config/Helm/docs;
- run build/image/runtime deploy;
- apply L4 recipes.

**Phase 2 (implementation):** L4 + one post-L4 build + L5 validation.

**Multi-language repository:** if the repository contains services in **other language
families** besides Python, run the common
[Multi-language scope gate](../opentelemetry-tracing-common/SKILL.md)
— ask the user **bulk vs single target** before any L4 edit.

### 3.1 User-facing briefs (mandatory)

Content and rules for all three briefs: common
[`reference/user-briefs.md`](../opentelemetry-tracing-common/reference/user-briefs.md).

Python adds to the L1 brief:

- **framework stack** — `service.framework` from L1: FastAPI (ASGI), Django, Flask (WSGI), or pure Python;
- **instrumentation mechanism** — Python has three, and the brief names which one is in play: `launcher` (the
  zero-code `opentelemetry-instrument` command), `instrumentor` (explicit `.instrument()` calls), or `hand-spans`;
- **app-server model** — worker count and whether `--preload` is set, because that decides where the SDK initializes.

### 3.2 Post-L4 build rule (once)

When L4 edits exist:

1. run fresh build and image once (see `recipes/fresh-build-and-image.md`);
2. do not rebuild again for runtime if L4 files are unchanged;
3. never validate runtime on stale image built before L4.

### 3.3 Runtime opt-in

After successful post-L4 build, ask user before runtime deploy.
If user declines or environment is unknown, set runtime status to `manual`.

### 3.4 Runtime order

Stand, order, assertions, and teardown: common
[`recipes/validation-stack.md`](../opentelemetry-tracing-common/recipes/validation-stack.md) and the
[Python delta](recipes/validation-stack.md). Never do a Jaeger-first pass/fail.

### 3.5 Post-validation cleanup (mandatory after runtime `pass`)

When `validationPlan.runtime.status` is `pass`, run
[`recipes/validation-cleanup.md`](../opentelemetry-tracing-common/recipes/validation-cleanup.md). See common
[`models/5-validation.md`](../opentelemetry-tracing-common/models/5-validation.md)
§5.4.

## 4. Output contract

The artifacts are in-session data, never files on disk — common
[`SKILL.md`](../opentelemetry-tracing-common/SKILL.md) §Where the artifacts live.

- `discovery-result` → [`schemas/L1-discovery-result.schema.json`](schemas/L1-discovery-result.schema.json)
- `capability-result` → common [`schemas/L2-capability-result.schema.json`](../opentelemetry-tracing-common/schemas/L2-capability-result.schema.json)
- `maturity-result` → common [`schemas/L3-maturity-result.schema.json`](../opentelemetry-tracing-common/schemas/L3-maturity-result.schema.json)
- `migration-plan` → common [`schemas/L4-migration-plan.schema.json`](../opentelemetry-tracing-common/schemas/L4-migration-plan.schema.json),
  including the embedded `validationPlan`

## 5. Non-negotiable rules

| Rule | Reason |
| --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Platform contract is binding | Must enforce `TRACING_*`, OTLP `http/protobuf`, `b3multi`, `parentbased_traceidratio`, `${name}-${namespace}`, endpoint filtering, trace IDs in logs |
| Evidence-first | Every claim cites file/path/env key |
| No semantic auto-rename | Semantic-convention renames are proposals, not automatic edits |
| One tracing stack | Final state cannot keep legacy Zipkin/OpenTracing/Jaeger as active stack |
| One instrumentation mechanism | Do not run the `opentelemetry-instrument` auto-launcher and manual `.instrument()` for the same library — double instrumentation can duplicate spans |
| Sampling & propagation mandatory | Validation fails if unknown or unverified |
| Defer versions | Read versions from `requirements.txt`/`pyproject.toml`, never hardcode versions in skill text |
| Sync docs on L4 | If L4 changes config/env/deps, update service docs in the same pass |
| Fresh post-L4 build | Runtime pass requires post-L4 dependency reinstall + image provenance |
| End-to-end only when stand is healthy | Runtime `pass` needs stand health + log triage before Jaeger (§3.4; common L5) |
| No Jaeger-first pass | Jaeger spans while SUT crash-loops or not Ready are not end-to-end pass — fix the stand first |

## 6. File index

- Layers: [`models/`](models/) — L1 discovery, the Python L4 framework gate, and the L5 Python delta
  (L2 and L3 are common)
- Schema: [`schemas/L1-discovery-result.schema.json`](schemas/L1-discovery-result.schema.json)
- Detection signatures: [`reference/detection-rules.md`](reference/detection-rules.md)
- Framework coverage: [`reference/framework-coverage.md`](reference/framework-coverage.md)
- Build blockers (Python delta): [`reference/build-preconditions.md`](reference/build-preconditions.md)
- Runtime install discovery (Python delta): [`reference/service-installation-discovery.md`](reference/service-installation-discovery.md)
- Recipes: [`recipes/`](recipes/) — L4 apply, `fresh-build-and-image`, and the `validation-stack` delta
- Shared core: [`opentelemetry-tracing-common/SKILL.md`](../opentelemetry-tracing-common/SKILL.md)
