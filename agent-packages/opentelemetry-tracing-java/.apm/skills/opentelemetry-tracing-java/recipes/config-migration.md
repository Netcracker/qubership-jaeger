# Recipe — configuration migration

Concrete config mappings for Layer 4 **§4.2** (`configMigration`) — see common
[`models/4-transformation.md`](../../opentelemetry-tracing-common/models/4-transformation.md).
Resolve the export target with
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md) §Export. Flag every
mapping that is **not 1:1**.

## Export endpoint

| From | To | 1:1? |
| --- | --- | --- |
| `management.zipkin.tracing.endpoint=http://zipkin:9411` | `OTEL_EXPORTER_OTLP_ENDPOINT=http://${TRACING_HOST}:4318/v1/traces` | no — protocol Zipkin→OTLP, port 9411→4318 |
| `JAEGER_AGENT_HOST` + `JAEGER_AGENT_PORT` | `OTEL_EXPORTER_OTLP_ENDPOINT=http://${TRACING_HOST}:4318/v1/traces` | no — UDP agent model removed |
| `JAEGER_ENDPOINT=http://jaeger:14268/api/traces` | `OTEL_EXPORTER_OTLP_ENDPOINT=http://${TRACING_HOST}:4318/v1/traces` | no — Thrift→OTLP |
| hardcoded collector URL in code | env/Helm-driven endpoint | no — move out of code |

## Sampling

| From                                                                     | To                                                                              | Note                                        |
|--------------------------------------------------------------------------|---------------------------------------------------------------------------------|---------------------------------------------|
| `spring.sleuth.sampler.probability`                                      | `management.tracing.sampling.probability`                                       | semantics preserved                         |
| Jaeger `JAEGER_SAMPLER_TYPE=probabilistic` + `JAEGER_SAMPLER_PARAM=0.01` | `OTEL_TRACES_SAMPLER=parentbased_traceidratio` + `OTEL_TRACES_SAMPLER_ARG=0.01` | map ratio; prefer parent-based              |
| platform `TRACING_SAMPLER_PROBABILISTIC`                                 | framework sampler ratio                                                         | wire platform value into the chosen sampler |

Production sampling must not be 100% unless explicitly approved.

## Propagation

**The migration preserves the wire format; it does not change it.** Rules and
rationale: common
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Propagation. In short: carry the configured inject format across, raise a
conflict with the contract as a **question** to the user, and on a greenfield
service ask the user to pick `B3` / `B3_MULTI` / `W3C` / a multi-format set
rather than choosing silently.

| From               | To                                                        | Note                                                         |
|--------------------|------------------------------------------------------------|--------------------------------------------------------------|
| Brave B3 (default) | same format on the OTel stack (`b3multi`)                  | 1:1 — property path changes, wire format does not            |
| Jaeger propagation | same format (`jaeger`) until peers move                    | a move to `b3multi`/`w3c` is a **separate**, fleet-wide task |
| mixed/unknown      | resolve the effective inject format first                  | ask the user before writing a row; never guess               |
| nothing configured | user's explicit choice, contract default `b3multi` offered | record the choice in the plan `note`                         |

### Per-framework surfaces

**Extract** order is priority, and **the winning end differs per framework** —
the same list means opposite things on Boot and on Quarkus. The user states
which format should win; **the agent derives the list order** from this table.
Never ask a developer which end wins.

**Inject** ignores order entirely: a composite writes **every** configured
format. On a single-list surface you cannot emit only one format without custom
code — only Boot's `produce`/`consume` split gives that control.

| Framework     | Inject                                              | Extract    | Extract winner                                                                                                            | Scope                             |
|---------------|-----------------------------------------------------|------------|---------------------------------------------------------------------------------------------------------------------------|-----------------------------------|
| Quarkus       | `quarkus.otel.propagators` — **all** listed written | same list  | **last** (`MultiTextMapPropagator`)                                                                                       | **build-time** — rebuild required |
| Spring Boot 3 | `…propagation.produce` — all listed written         | `.consume` | **first** (`CompositePropagationFactory$CompositePropagation` Brave bridge; `CompositeTextMapPropagator` OTel bridge)      | runtime                           |
| Spring Boot 4 | `…propagation.produce` — all listed written         | `.consume` | **first** — `…micrometer.tracing.opentelemetry.autoconfigure.CompositeTextMapPropagator`, `extract` identical to Boot 3    | runtime                           |
| Pure Java     | `OTEL_PROPAGATORS` — one list, **all** written      | same list  | **last** (`MultiTextMapPropagator`)                                                                                       | runtime                           |

Verified by disassembly: `spring-boot-actuator-autoconfigure:3.5.11`,
`spring-boot-micrometer-tracing-opentelemetry:4.0.2`, `opentelemetry-context:1.57.0`.

Do **not** set `management.tracing.propagation.type` next to `produce`/`consume`:
it is itself a list and overrides both, silently discarding the lenient
`consume` default.

Spring Boot defaults, when neither property is set, are **asymmetric**:

```yaml
management:
  tracing:
    propagation:
      consume: [W3C, B3, B3_MULTI]   # framework default
      produce: [W3C]                 # framework default — B3 fleets break outbound
```

An unconfigured Boot service in a B3 fleet therefore looks healthy on incoming
requests and breaks trace continuity on outgoing ones. Always set `produce`
explicitly; do not read "no key" as "no propagation".

Multi-format is a valid target: several formats on `consume`, one (or several)
on `produce`. Nothing extra is needed around it — the assumption is that adjacent
tooling does not overwrite an already-present context.

## Target config shapes

Binding rules come from
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md).
Framework-specific shapes are in **this recipe** (Spring Boot below) and
[`../reference/quarkus-platform-contract.md`](../reference/quarkus-platform-contract.md)
(Quarkus). Do not invent a different shape. Key points the target must satisfy:

- `TRACING_ENABLED` drives the SDK on/off toggle.
- exporter OTLP `http/protobuf` to `http://${TRACING_HOST}:4318/v1/traces`.
- propagation set to the **preserved or user-chosen** format (contract default
  `b3multi`) on the framework surface from the table above
  (+ `opentelemetry-extension-trace-propagators` for any B3 format).
- `sampler: parentbased_traceidratio` with `sampler.args=${TRACING_SAMPLER_PROBABILISTIC}`.
- `service.name` built from app name + injected `NAMESPACE`.
- probe/metrics/management endpoints excluded; `traceId`/`spanId` added to logs
  (see [`logging-correlation.md`](logging-correlation.md)).

### Quarkus adjustments (mandatory when `framework` is Quarkus)

Spring SpEL toggles and platform URL literals do **not** map 1:1 to Quarkus.
Follow [`../reference/quarkus-platform-contract.md`](../reference/quarkus-platform-contract.md):

| Platform / Spring idea                                | Quarkus target                                                                               | 1:1?                             |
|-------------------------------------------------------|----------------------------------------------------------------------------------------------|----------------------------------|
| SpEL / nested `TRACING_ENABLED` → SDK off             | `QUARKUS_OTEL_SDK_DISABLED=false` when enabled (Helm env or direct property)                 | no                               |
| endpoint `http://${TRACING_HOST}:4318/v1/traces`      | `quarkus.otel.exporter.otlp.endpoint=http://${TRACING_HOST}:4318` + `protocol=http/protobuf` | no — Quarkus appends `v1/traces` |
| `tracing.sdk.disabled.${TRACING_ENABLED}` nested keys | reject; mark high risk in plan `gaps` if present                                             | no                               |

#### Legacy `quarkus.jaeger.*` keys (retired extension)

After swapping `quarkus-jaeger` for `quarkus-opentelemetry`
([`dependency-migration.md`](dependency-migration.md)), remove every
`quarkus.jaeger.*` key — they are ignored by the OTel extension, so propagation
and sampling silently fall back to defaults unless redeclared under
`quarkus.otel.*`:

| From (`quarkus.jaeger.*`)                       | To (`quarkus.otel.*`)                                                                                   | Note                                                                                                    |
|-------------------------------------------------|---------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| `quarkus.jaeger.endpoint` (`:14268/api/traces`) | `quarkus.otel.exporter.otlp.endpoint=http://${TRACING_HOST}:4318`                                       | legacy collector → OTLP base URL                                                                        |
| `quarkus.jaeger.service-name`                   | `quarkus.otel.service.name` (or `quarkus.application.name`)                                             | must compose `${name}-${namespace}`                                                                     |
| `quarkus.jaeger.sampler-type` / `sampler-param` | `quarkus.otel.traces.sampler=parentbased_traceidratio` + `sampler.arg=${TRACING_SAMPLER_PROBABILISTIC}` | map ratio semantics                                                                                     |
| `quarkus.jaeger.propagation`                    | `quarkus.otel.propagators=<same format>`                                                                | keep the format; **build-time** — needs a rebuild; + `opentelemetry-extension-trace-propagators` for B3 |

#### Service name (Quarkus)

Without an explicit value Quarkus exports the **artifact ID** as
`service.name` — that violates the `${name}-${namespace}` contract. Set:

```properties
quarkus.application.name=${microservice.name:app}-${NAMESPACE:local}
```

using the same namespace env the deployment chart injects (Downward API or
deployer variable).

Emit Helm/K8s env for runtime validation when the image is pre-built:

```text
QUARKUS_OTEL_SDK_DISABLED=false
QUARKUS_OTEL_EXPORTER_OTLP_ENDPOINT=http://${TRACING_HOST}:4318
```

Pure Java / env equivalent:

```text
OTEL_EXPORTER_OTLP_ENDPOINT=http://${TRACING_HOST}:4318/v1/traces
OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
OTEL_PROPAGATORS=b3multi
OTEL_TRACES_SAMPLER=parentbased_traceidratio
OTEL_TRACES_SAMPLER_ARG=${TRACING_SAMPLER_PROBABILISTIC}
OTEL_SERVICE_NAME=${APP_NAME}-${NAMESPACE}
```

`TRACING_HOST` is host-only (default `nc-diagnostic-agent`); confirm the
proxy/collector and port before writing the endpoint.

### Spring Boot 3 adjustments (when parent is 3.x)

Drive SDK on/off from `TRACING_ENABLED` via explicit SpEL (not nested
SmallRye-style keys). Canonical platform shape for the `otel.*` surface:

```yaml
otel:
  sdk:
    disabled: '#{"${TRACING_ENABLED:}".equals("true")?"false":"true"}'
  propagators:
    - b3multi
  traces:
    exporter: otlp
    sampler: parentbased_traceidratio
    sampler.args: ${TRACING_SAMPLER_PROBABILISTIC}
  exporter:
    otlp:
      traces:
        protocol: http/protobuf
        endpoint: http://${TRACING_HOST}:4318/v1/traces
  service.name: ${spring.application.name}-${NAMESPACE:local}
```

The `otel.propagators` list above is the OTel-native surface (winner **last**).
When the Micrometer bridge owns propagation instead, use
`management.tracing.propagation.produce` / `.consume` — winner **first**. Do not
mix both surfaces in one service.

Pair with `management.tracing.enabled`, OTLP endpoint, the preserved propagation
format, and `management.tracing.sampling.probability` wired to
`${TRACING_SAMPLER_PROBABILISTIC}` — same contract as Boot 4, different property
paths (see Boot 4 table below when upgrading).

### Spring Boot 4 adjustments (mandatory when parent is 4.x)

Boot 4 renamed tracing export properties. Boot 3 keys still parse in YAML but
**fail** at startup with `PropertiesMigrationListener` ("uses an incompatible
target type") and OTLP export stays off.

| Boot 3 / legacy key                | Boot 4 key                                                       |
|------------------------------------|------------------------------------------------------------------|
| `management.tracing.enabled`       | `management.tracing.export.enabled`                              |
| `management.otlp.tracing.endpoint` | `management.opentelemetry.tracing.export.otlp.endpoint`          |
| (implicit)                         | `management.tracing.export.otlp.enabled: true` when export is on |

**Remove** the legacy keys when adding the Boot 4 ones — do not leave both
generations in config (the old keys either fail startup or mislead readers
into thinking they are active).

Example shape (platform contract unchanged — only key paths differ):

```yaml
management:
  opentelemetry:
    resource-attributes:
      "service.name": ${spring.application.name}-${NAMESPACE:local}
    tracing:
      export:
        otlp:
          endpoint: http://${TRACING_HOST:nc-diagnostic-agent}:4318/v1/traces
  tracing:
    export:
      enabled: ${TRACING_ENABLED:false}
      otlp:
        enabled: true
    propagation:
      produce: [B3_MULTI]            # outbound — set explicitly, default is [W3C]
      consume: [B3_MULTI, W3C]       # inbound — lenient, first in the list wins
    sampling:
      probability: ${TRACING_SAMPLER_PROBABILISTIC}
```

Wire `TRACING_SAMPLER_PROBABILISTIC` from deployment env — do not default to
`1.0` in production config. For L5 smoke only, set `TRACING_SAMPLER_PROBABILISTIC=1.0`
via env (see [`validation-stack.md`](validation-stack.md)).

Also requires `spring-boot-micrometer-tracing-opentelemetry` on the classpath —
see [`dependency-migration.md`](dependency-migration.md). Config-only fixes without
the starter produce log `traceId`/`spanId` but no Jaeger service.
