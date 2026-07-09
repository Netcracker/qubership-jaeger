# opentelemetry-tracing-java

APM skill for **Java** services (Spring Boot, Quarkus, **Pure Java**): a five-layer pipeline that audits an unknown
service's tracing, scores its maturity, and generates an OpenTelemetry migration and validation plan. It also fixes
**Kafka/async context loss** and **verifies sampling and propagation** before a task is closed.

Part of the multi-language tracing program — see [`../README.md`](../README.md)
(Go, Python, JS/TS planned).

Sources in this monorepo and sibling clones:

| Topic                           | Location                                                           |
|---------------------------------|--------------------------------------------------------------------|
| Skill package                   | `agent-packages/opentelemetry-tracing-java/`                       |
| Program scope (all languages)   | `agent-packages/README.md`                                         |
| Jaeger Helm / collector ports   | `charts/qubership-jaeger/values.yaml`, `README.md`, `docs/`        |
| OTeC ingress & Jaeger export    | `../qubership-open-telemetry-collector/docs/installation-notes.md` |
| Java libraries (external clone) | `../qubership-core-java-libs/`                                     |

Status: **draft** — language-specific Java layer aligned with umbrella core.
APM version `0.2.10` (Spring Boot 4 OTLP starter + export property keys; stand health gate before Jaeger; explicit L5 runtime order; one post-L4 Maven/image build; L3 decision matrix in umbrella `3-maturity.md`).

## Architecture

The skill is an analysis pipeline orchestrated by
[`SKILL.md`](.apm/skills/opentelemetry-tracing-java/SKILL.md). Each layer reads
the previous artifact and emits the next:

| Layer             | File                         | Output                                             |
|-------------------|------------------------------|----------------------------------------------------|
| L1 Discovery      | `models/1-discovery.md`      | `discovery-result.json`                            |
| L2 Capability     | `models/2-capability.md`     | delegated to umbrella                              |
| L3 Maturity       | `models/3-maturity.md`       | delegated to umbrella                              |
| L4 Transformation | `models/4-transformation.md` | shared plan + Java framework-family/mechanism gate |
| L5 Validation     | `models/5-validation.md`     | shared tiers + Java runtime execution rules        |

## Naming convention (L1-L5)

To keep language packages and umbrella aligned, use this convention:

- `models/<N>-<name>.md` for layer documents (`1-discovery` ... `5-validation`);
- `schemas/L<N>-<artifact-name>.schema.json` for machine contracts (e.g. `L1-discovery-result.schema.json`);
- `reference/<topic>.md` for policy/rules and source mapping;
- `recipes/<concern>.md` for executable migration procedures.

Ownership: Java package keeps `L1` + Java-specific `reference/recipes`; umbrella
keeps shared `L2-L5`, shared schemas, and shared policy references.

Supporting material:

- `schemas/` — `L1-discovery-result.schema.json` + redirects (`L2`–`L4`) to umbrella schemas
- `reference/` — local Java detection rules, framework coverage, build preconditions + redirects to umbrella shared references
- `recipes/` — dependency / config / code / async-context / logging-correlation / fresh-build-and-image / validation-stack migration recipes; shared L5 stand-health, log-error-triage, and validation-cleanup in umbrella
- shared core: `../opentelemetry-tracing-umbrella/`

Examples in this package were intentionally removed. Use
[`platform-tracing-guide.md`](../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md)
and official framework documentation for reference shapes.

## Local check

From the repository root:

```shell
apm install -t <target>
apm compile -t <target>
```

Use the compile target your APM setup expects. See [`../README.md`](../README.md) §Installation for target-specific outputs.
