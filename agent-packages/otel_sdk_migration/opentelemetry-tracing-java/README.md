# opentelemetry-tracing-java

APM skill for **Java** services (Spring Boot, Quarkus, pure Java): a five-layer pipeline that audits an unknown
service's tracing, scores maturity, and produces an OpenTelemetry migration and validation plan. It also fixes
Kafka/async context loss and verifies sampling and propagation before a task is closed.

Part of the multi-language tracing program — see [`../README.md`](../README.md).

## Architecture

The skill is orchestrated by
[`SKILL.md`](.apm/skills/opentelemetry-tracing-java/SKILL.md). Each layer reads
the previous artifact and emits the next:

| Layer             | File                            | Output                                             |
| ----------------- | ------------------------------- | -------------------------------------------------- |
| L1 Discovery      | `models/1-discovery.md`         | `discovery-result`                                 |
| L2 Capability     | common `models/2-capability.md` | `capability-result`                                |
| L3 Maturity       | common `models/3-maturity.md`   | `maturity-result`                                  |
| L4 Transformation | `models/4-transformation.md`    | shared plan + Java framework-family/mechanism gate |
| L5 Validation     | `models/5-validation.md`        | shared tiers + Java runtime execution rules        |

## Supporting material

The file index — schemas, detection rules, framework coverage, the Quarkus platform contract, recipes, and which
pieces come from common — is [`SKILL.md`](.apm/skills/opentelemetry-tracing-java/SKILL.md) §6, the copy the agent
reads and the only place they are listed. Shared core:
[`../opentelemetry-tracing-common/`](../opentelemetry-tracing-common/).

## Source-of-truth policy

- Qubership platform contract comes from common
  [`platform-tracing-guide.md`](../opentelemetry-tracing-common/.apm/skills/opentelemetry-tracing-common/reference/platform-tracing-guide.md)
  (contracted `TRACING_*`, OTLP format, B3/B3Multi, sampling, namespace in `service.name`,
  endpoint filtering, and log correlation).
- Java-specific detection rules and recipes live in this package. This package ships no example snippets — take
  reference shapes from the contract above and from the framework's own documentation.
- Package version lives in [`apm.yml`](apm.yml), the manifest APM reads. A second copy here would only drift.

## Local check

From this package directory, or from `agent-packages/otel_sdk_migration/` when installing the whole program:

```shell
apm install -t claude
```
