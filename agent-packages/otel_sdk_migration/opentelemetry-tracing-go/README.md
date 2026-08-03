# opentelemetry-tracing-go

APM skill for **Go** services (Fiber with platform HTTP wrapper, stdlib `net/http`, Gin/Echo):
a five-layer pipeline that audits an unknown service's tracing, scores maturity,
and produces an OpenTelemetry migration and validation plan.

Part of the multi-language tracing program — see [`../README.md`](../README.md).

## Architecture

The skill is orchestrated by
[`SKILL.md`](.apm/skills/opentelemetry-tracing-go/SKILL.md). Each layer reads
the previous artifact and emits the next:

| Layer             | File                            | Output                                          |
| ----------------- | ------------------------------- | ----------------------------------------------- |
| L1 Discovery      | `models/1-discovery.md`         | `discovery-result`                              |
| L2 Capability     | common `models/2-capability.md` | `capability-result`                             |
| L3 Maturity       | common `models/3-maturity.md`   | `maturity-result`                               |
| L4 Transformation | `models/4-transformation.md`    | shared plan + Go framework-stack/mechanism gate |
| L5 Validation     | `models/5-validation.md`        | shared tiers + Go runtime execution rules       |

## Supporting material

- `schemas/` — `L1-discovery-result.schema.json`; the L2–L4 schemas live in common and are linked directly
- `reference/` — Go detection rules and framework coverage, plus the local deltas on the common
  build-preconditions and install-discovery files
- `recipes/` — dependency, config, code, async-context, and logging-correlation migration recipes, plus
  `fresh-build-and-image` and the `validation-stack` delta; the shared L5 recipes live in common
- shared core: `../opentelemetry-tracing-common/`

## Source-of-truth policy

- Qubership platform contract comes from common
  [`platform-tracing-guide.md`](../opentelemetry-tracing-common/.apm/skills/opentelemetry-tracing-common/reference/platform-tracing-guide.md)
  (contracted `TRACING_*`, OTLP format, B3/B3Multi, sampling, namespace in `service.name`,
  endpoint filtering, and log correlation).
- Go-specific detection rules and recipes live in this package.

## Local check

From this package directory, or from `agent-packages/otel_sdk_migration/` when installing the whole program:

```shell
apm install -t claude
```

`apm compile` is a separate concern and this repository does not need it — see
[`../README.md`](../README.md) §Installation.
