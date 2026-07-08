# Recipe — dependency migration

Concrete `remove` / `add` / `upgrade` moves for Layer 4 **§4.1** (`dependencyMigration`) — see umbrella
[`models/4-transformation.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/models/4-transformation.md).
Keyed on discovery. Read versions from the repo's BOM/`pom.xml`; never pin here.

## Choosing the target instrumentation

The framework family decided in [Layer 4 Step 0](../models/4-transformation.md)
selects the row; it is **not** a free choice. Pick the path that matches the
detected runtime, then stay on it for config and code.

| Runtime         | Required/preferred OTel path                                          | Agent allowed? |
|-----------------|----------------------------------------------------------------------|----------------|
| Spring Boot 3   | Micrometer Tracing + `micrometer-tracing-bridge-otel` + OTLP exporter | yes (zero-touch, not with the bridge) |
| Spring Boot 4   | Same bridge/exporter **plus** `spring-boot-micrometer-tracing-opentelemetry` (official Boot OTLP autoconfig) | yes (zero-touch, not with the bridge) |
| Quarkus         | `quarkus-opentelemetry` extension (**required**)                     | **no** — forbidden, breaks Vert.x |
| Pure Java       | `opentelemetry-sdk` + `opentelemetry-exporter-otlp` (+ propagators)   | yes (zero-touch) |

Agent vs SDK (only where the agent is allowed): choose the **agent** when the
service has little or no manual instrumentation and you want broad auto-coverage
without code edits; choose the **SDK** when the service already creates custom
spans or needs fine control. Do not run both unless deliberately bridging.

**Never attach `opentelemetry-javaagent` to a Quarkus service.** If install docs
require a build the user cannot run, record the blocker in `gaps` — see
[`../reference/build-preconditions.md`](../reference/build-preconditions.md) and
[`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md).

### Spring Boot 4 (parent `spring-boot-starter-parent` 4.x)

Read the Boot version from the repo parent POM/BOM — do not assume Boot 3.

On Boot 4, `micrometer-tracing-bridge-otel` + `opentelemetry-exporter-otlp` alone
**do not** activate OTLP export. Micrometer may create spans and log
correlation may work, but Jaeger stays empty until the official Boot module is
present.

**Mandatory add** (managed by the Boot BOM — no version pin):

```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-micrometer-tracing-opentelemetry</artifactId>
</dependency>
```

Greenfield Boot 4 services may use `spring-boot-starter-opentelemetry` instead;
when migrating from Brave/Zipkin on an existing service, prefer the module above
alongside the bridge and propagators.

Pair with Boot 4 config keys in [`config-migration.md`](config-migration.md)
(`management.tracing.export.*`, `management.opentelemetry.tracing.export.otlp.*`).
Boot 3 keys are rejected at startup (`PropertiesMigrationListener` / incompatible
target type) and leave export disabled even when `TRACING_ENABLED=true`.

After adding the starter, rebuild the image and roll the workload before L5
runtime tracing checks.

## Per-legacy-stack moves

### Brave / Zipkin

- remove: `io.zipkin.brave:brave*`, `io.zipkin.reporter2:*`,
  `io.micrometer:micrometer-tracing-bridge-brave`
- add: `io.micrometer:micrometer-tracing-bridge-otel`,
  `io.opentelemetry:opentelemetry-exporter-otlp`

### Spring Cloud Sleuth

- remove: `spring-cloud-starter-sleuth`, `spring-cloud-sleuth-zipkin`
- add: Boot 3 Micrometer Tracing bridge + OTLP exporter (Sleuth is end-of-life
  on Boot 3; there is no in-place upgrade)

### Jaeger client

- remove: `io.jaegertracing:jaeger-client` / `jaeger-core` / `jaeger-thrift`
- add: `opentelemetry-sdk` + `opentelemetry-exporter-otlp` (the Jaeger
  agent/UDP model is gone — OTLP replaces it)

### OpenTracing

- remove: `io.opentracing:opentracing-api` / `opentracing-util` and any
  `opentracing-*` instrumentation shims
- add: OTel API/SDK via the framework path above; migrate code per
  [`code-migration.md`](code-migration.md)

### Quarkus Jaeger extension (`quarkus-jaeger`)

The Jaeger extension is retired (moved out of the Quarkus core platform) and
exports to the legacy Jaeger collector (`:14268`), not OTLP `:4318`.

- remove: `io.quarkus:quarkus-jaeger` (or relocated `io.quarkiverse.jaeger:*`)
  and `quarkus-smallrye-opentracing` when present
- add: `io.quarkus:quarkus-opentelemetry` (the standard OTLP/propagator/sampler
  path on Quarkus 3.x)
- migrate all `quarkus.jaeger.*` properties to `quarkus.otel.*` — see
  [`config-migration.md`](config-migration.md); leftover `quarkus.jaeger.*`
  keys are silently ignored after the extension swap

## Canonical platform additions

Beyond the per-stack bridge/exporter above, the platform contract
([`platform-tracing-guide.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md))
expects these on the target side:

- `io.opentelemetry:opentelemetry-bom` (import) and
  `io.opentelemetry.instrumentation:opentelemetry-instrumentation-bom` (import)
  in `dependencyManagement`.
- `io.opentelemetry:opentelemetry-semconv` (runtime).
- `io.opentelemetry:opentelemetry-extension-trace-propagators` — required for
  `b3`/`b3multi`.
- Log correlation MDC dependency — `opentelemetry-log4j-context-data-2.17-autoconfigure`
  (log4j) or `opentelemetry-logback-mdc-1.0` (logback); skip if a CloudCore lib
  already supplies trace fields. See [`logging-correlation.md`](logging-correlation.md).

## Guardrails

- Before removing a legacy artifact, resolve the dependency tree. If it is
  pulled transitively by a Qubership library, do **not** exclude it until you
  confirm that library supports the OTel path. Record the guard in the plan
  (`guardedBy`).
- Manage OTel versions through a BOM
  (`io.opentelemetry:opentelemetry-bom`) or the service parent POM. Do not pin
  individual OTel artifacts to conflicting versions.
- Jaeger client and OpenTracing libraries are **retired** (no community fixes);
  always treat them as removal targets, never as something to keep.
