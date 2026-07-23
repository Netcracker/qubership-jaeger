# opentelemetry-tracing-go

APM skill for **Go** services (Fiber with platform HTTP wrapper, stdlib `net/http`, Gin/Echo):
a five-layer pipeline that audits an unknown service's tracing, scores maturity,
and produces an OpenTelemetry migration and validation plan.

Part of the multi-language tracing program — see [`../README.md`](../README.md).

## Architecture

The skill is orchestrated by
[`SKILL.md`](.apm/skills/opentelemetry-tracing-go/SKILL.md). Each layer reads
the previous artifact and emits the next:

| Layer             | File                         | Output                                          |
|-------------------|------------------------------|-------------------------------------------------|
| L1 Discovery      | `models/1-discovery.md`      | `discovery-result.json`                         |
| L2 Capability     | `models/2-capability.md`     | delegated to common                           |
| L3 Maturity       | `models/3-maturity.md`       | delegated to common                           |
| L4 Transformation | `models/4-transformation.md` | shared plan + Go framework-stack/mechanism gate |
| L5 Validation     | `models/5-validation.md`     | shared tiers + Go runtime execution rules       |

## Supporting material

- `schemas/` — `L1-discovery-result.schema.json` + redirects (`L2`–`L4`) to common schemas
- `reference/` — local Go detection rules, framework coverage, build preconditions, service installation discovery
- `recipes/` — dependency / config / code / async-context / logging-correlation / fresh-build-and-image / validation-stack migration recipes; shared L5 stand-health, log-error-triage, and validation-cleanup in common
- shared core: `../opentelemetry-tracing-common/`

## Source-of-truth policy

- Qubership platform contract comes from common
  [`platform-tracing-guide.md`](../opentelemetry-tracing-common/.apm/skills/opentelemetry-tracing-common/reference/platform-tracing-guide.md)
  (contracted `TRACING_*`, OTLP format, B3/B3Multi, sampling, namespace in `service.name`,
  endpoint filtering, and log correlation).
- Go-specific detection rules and recipes live in this package.

## Local check

From this package directory (`agent-packages/opentelemetry-tracing-go/`) or repository root if root `apm.yml` lists this package:

```shell
apm install -t <target>
apm compile -t <target>
```
