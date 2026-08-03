# Layer 1 — Discovery (Python)

**Goal:** enumerate every existing element of tracing implementation.
Discovery reports what exists, not whether it works.

- **Input:** repository root (Python source, dependency manifests, config, deployment, Helm/k8s).
- **Output:** `discovery-result.json` validated by
  [`../schemas/L1-discovery-result.schema.json`](../schemas/L1-discovery-result.schema.json).
- **Detection signatures:** [`../reference/detection-rules.md`](../reference/detection-rules.md).

Run sections **1.0–1.6**; emit every required JSON object. Missing evidence →
`unknown` or empty arrays per schema; record why in `gaps` — do not omit sections.

## 1.0 Framework discovery

Set `service.framework` (schema enum) and optional `service.name` from
[`../reference/detection-rules.md`](../reference/detection-rules.md) §Framework
signatures. Classify to a first-class value only on confident evidence, otherwise
`unknown` — best-effort handling and the instrumentor mapping:
[`../reference/framework-coverage.md`](../reference/framework-coverage.md).

## 1.1 Dependency discovery

Inputs:

- `requirements.txt` (and `requirements/*.txt`), `pyproject.toml`, `setup.cfg`,
  `setup.py`, `poetry.lock`, `Pipfile`/`Pipfile.lock`, `uv.lock`;
- optional `pip freeze` / `pip list` or `opentelemetry-bootstrap -a list` output.

Classify every tracing artifact into a bucket and set the aggregate flags
(`hasOtelApi`, `hasOtelSdk`, `hasExporter`, `hasLegacy`) — distribution catalogue
and bucket assignments:
[`../reference/detection-rules.md`](../reference/detection-rules.md) §Dependency
signatures.

## 1.2 Configuration discovery

Inspect config/env locations:

- `.env`, Helm values/templates, Deployment env vars;
- app settings modules (Django `settings.py`, Pydantic `Settings`, `os.environ` reads, `python-dotenv`);
- hardcoded tracing constants and programmatic SDK setup in `.py` files.

Collect:

- export endpoint/protocol/target guess;
- propagation **inject** and **extract** sets (separately — see below) and per-component wiring (HTTP/Kafka/async);
- sampler type and ratio.

### Propagation: two sets, resolved from the actual configuration

Record `propagation.inject` and `propagation.extract` separately, in the order
written — do not reorder or dedupe. Why the two directions differ and which end of
a composite wins on extract:
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Propagation. Both sources are `runtime` scope in Python (interpreted — there is
no build-time propagation surface): `OTEL_PROPAGATORS` and programmatic
`set_global_textmap(...)`.

Read the propagator **class**, not just the presence of B3 — `B3SingleFormat`
emits the single `b3` header while `B3MultiFormat` emits `X-B3-*`, and the legacy
alias `B3Format` is the **multi** one (`detection-rules.md` §Code signatures).
Verify against the b3 version in the repo's manifest, not against a version cited
elsewhere: guide §Verify constructor defaults.

If **both** `OTEL_PROPAGATORS` and a programmatic `set_global_textmap(...)` are
present, the programmatic call wins (it overwrites the global after autoconfigure).
Record the programmatic value as the effective one and mark the env value overridden.

## 1.3 API discovery (AST/symbol)

Scan `.py` sources for the OTel, legacy, and framework-instrumentor symbols
catalogued in [`../reference/detection-rules.md`](../reference/detection-rules.md)
§Code signatures. Record `family`, `symbol`, `file`, `line` for each hit.

## 1.4 Instrumentation discovery

Classify `instrumentation.mode` (`auto` / `manual` / `mixed` / `none`) from
`detection-rules.md` §Instrumentation mode signatures.

## 1.5 Async-boundary discovery

Record each context-loss candidate with its boundary type, and set
`contextWrapper` true only when context is explicitly propagated. Boundary
catalogue and the `contextvars` exemption (plain `async`/`await` is **not** a loss
boundary): [`../reference/detection-rules.md`](../reference/detection-rules.md)
§Async-boundary signatures.

## 1.6 Platform-contract discovery

Resolve every facet of `platformContract` from the Python signals:
[`../reference/detection-rules.md`](../reference/detection-rules.md)
§Platform-contract signatures. For missing inspectable evidence, use `unknown`
and record `gaps`.

## User-facing brief (mandatory)

Post the **L1 Discovery brief** — content and rules in common
[`reference/user-briefs.md`](../../opentelemetry-tracing-common/reference/user-briefs.md), language additions in
[`../SKILL.md`](../SKILL.md) §3.1. Do not proceed to L2 until it is posted.
