# opentelemetry-tracing-java

APM skill for **Java** services (Spring Boot, Quarkus, **Pure Java**): a five-layer pipeline that audits an unknown
service's tracing, scores its maturity, and generates an OpenTelemetry migration and validation plan. It also fixes
**Kafka/async context loss** and **verifies sampling and propagation** before a task is closed.

Part of the multi-language tracing program — see [`../README.md`](../README.md)
(Go, Python, and TypeScript packages ship alongside this one).

Sources in this monorepo and sibling clones:

| Topic                           | Location                                                           |
| ------------------------------- | ------------------------------------------------------------------ |
| Skill package                   | `agent-packages/otel_sdk_migration/opentelemetry-tracing-java/`    |
| Program scope (all languages)   | `agent-packages/otel_sdk_migration/README.md`                      |
| Jaeger Helm / collector ports   | `charts/qubership-jaeger/values.yaml`, `README.md`, `docs/`        |
| OTeC ingress & Jaeger export    | `../qubership-open-telemetry-collector/docs/installation-notes.md` |
| Java libraries (external clone) | `../qubership-core-java-libs/`                                     |

Status: **draft** — language-specific Java layer aligned with common core.
Package version lives in [`apm.yml`](apm.yml) — the manifest APM actually reads. Do not restate it here; a
second copy only drifts.

Current revision covers: Spring Boot 4 OTLP starter and export property keys; stand health gate before
Jaeger; one post-L4 Maven and image build; L2–L5 logic, shared reference, and shared L5 recipes in common.

## Architecture

The skill is an analysis pipeline orchestrated by
[`SKILL.md`](.apm/skills/opentelemetry-tracing-java/SKILL.md). Each layer reads
the previous artifact and emits the next:

| Layer             | File                            | Output                                             |
| ----------------- | ------------------------------- | -------------------------------------------------- |
| L1 Discovery      | `models/1-discovery.md`         | `discovery-result`                                 |
| L2 Capability     | common `models/2-capability.md` | `capability-result`                                |
| L3 Maturity       | common `models/3-maturity.md`   | `maturity-result`                                  |
| L4 Transformation | `models/4-transformation.md`    | shared plan + Java framework-family/mechanism gate |
| L5 Validation     | `models/5-validation.md`        | shared tiers + Java runtime execution rules        |

## Naming convention (L1-L5)

To keep language packages and common aligned, use this convention:

- `models/<N>-<name>.md` for layer documents (`1-discovery` ... `5-validation`);
- `schemas/L<N>-<artifact-name>.schema.json` for machine contracts (e.g. `L1-discovery-result.schema.json`);
- `reference/<topic>.md` for policy/rules and source mapping;
- `recipes/<concern>.md` for executable migration procedures.

Ownership: Java package keeps `L1` + Java-specific `reference/recipes`; common
keeps shared `L2-L5`, shared schemas, and shared policy references.

Supporting material:

- `schemas/` — `L1-discovery-result.schema.json`; the L2–L4 schemas live in common and are linked directly
- `reference/` — Java detection rules, framework coverage, and the Quarkus platform contract, plus the local
  deltas on the common build-preconditions file
- `recipes/` — dependency, config, code, async-context, and logging-correlation migration recipes, plus
  `fresh-build-and-image` and the `validation-stack` delta; the shared L5 recipes live in common
- shared core: `../opentelemetry-tracing-common/`

Examples in this package were intentionally removed. Use
[`platform-tracing-guide.md`](../opentelemetry-tracing-common/.apm/skills/opentelemetry-tracing-common/reference/platform-tracing-guide.md)
and official framework documentation for reference shapes.

## Local check

From this package directory, or from `agent-packages/otel_sdk_migration/` when installing the whole program:

```shell
apm install -t claude
```

`apm compile` is a separate concern and this repository does not need it — see
[`../README.md`](../README.md) §Installation.
