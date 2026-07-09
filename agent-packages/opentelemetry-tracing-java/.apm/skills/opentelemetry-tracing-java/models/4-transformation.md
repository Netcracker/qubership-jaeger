# Layer 4 — Transformation (Java)

Shared plan structure, algorithm, and section numbering (§4.1–§4.5):
[`opentelemetry-tracing-umbrella/models/4-transformation.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/models/4-transformation.md).

Run the **Java gate below before §4.1**. Then fill §4.1–§4.4 from recipes:

| Section | Recipe |
| --- | --- |
| §4.1 `dependencyMigration` | [`../recipes/dependency-migration.md`](../recipes/dependency-migration.md) |
| §4.2 `configMigration` | [`../recipes/config-migration.md`](../recipes/config-migration.md) + [`../recipes/logging-correlation.md`](../recipes/logging-correlation.md) (log patterns) |
| §4.3 `codeMigration` | [`../recipes/code-migration.md`](../recipes/code-migration.md) |
| §4.4 `asyncContextMigration` | [`../recipes/async-context-migration.md`](../recipes/async-context-migration.md) |

§4.5 `validationPlan` and documentation-on-apply rules: umbrella
[`models/4-transformation.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/models/4-transformation.md)
and [`5-validation.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/models/5-validation.md).

## Step 0 — Framework family decision (mandatory)

Read `discovery-result.service.framework` and pick exactly one target path.
Do not emit §4.1 or §4.2 rows before this is fixed.

| Family                                                           | Target instrumentation                                                | Config surface                                                                                                                             |
|------------------------------------------------------------------|-----------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------|
| Spring Boot 3                                                    | Micrometer Tracing + `micrometer-tracing-bridge-otel` + OTLP exporter | `application.yaml` (`management.*`, `otel.*`)                                                                                              |
| Spring Boot 4                                                    | Boot 3 stack **+** `spring-boot-micrometer-tracing-opentelemetry`     | `application.yaml` — Boot 4 `management.tracing.export.*` / `management.opentelemetry.tracing.export.otlp.*` (Boot 3 keys fail)            |
| Quarkus                                                          | `quarkus-opentelemetry` **extension** (build-time)                    | `application.properties` (`quarkus.otel.*`) — see [`../reference/quarkus-platform-contract.md`](../reference/quarkus-platform-contract.md) |
| Pure Java                                                        | `opentelemetry-sdk` + `opentelemetry-exporter-otlp` (+ propagators)   | env / programmatic SDK builder                                                                                                             |
| Best-effort (Micronaut, Helidon, Vert.x, Jakarta EE, Dropwizard) | framework OTel module if it exists, else SDK                          | framework config, else env                                                                                                                 |

Pull versions from the repository BOM/`pom.xml`; never pin them in the plan.

## Step 0b — Instrumentation-mechanism guardrails (mandatory)

After the family is chosen, validate the **mechanism** (extension / starter /
SDK / agent). Reject forbidden combinations in the plan.

| Family        | extension / starter                                                         | manual SDK                    | OTel Java agent (`-javaagent`)                    |
|---------------|-----------------------------------------------------------------------------|-------------------------------|---------------------------------------------------|
| Spring Boot 3 | preferred                                                                   | allowed                       | allowed (zero-touch), not with the starter bridge |
| Spring Boot 4 | **`spring-boot-micrometer-tracing-opentelemetry` required** for OTLP export | allowed with bridge + starter | allowed (zero-touch), not with the starter bridge |
| Quarkus       | **required**                                                                | n/a                           | **forbidden**                                     |
| Pure Java     | n/a                                                                         | preferred                     | allowed (zero-touch)                              |

**Quarkus + `-javaagent` is forbidden.** Quarkus instruments at build time via
`quarkus-opentelemetry`; the runtime agent double-instruments and breaks Vert.x
(`NoSuchFieldError` on virtual fields). If the extension cannot be added (see
[`../reference/build-preconditions.md`](../reference/build-preconditions.md)),
record the blocker in plan `gaps` and **do not** fall back to the agent.

End with **one** instrumentation mechanism. Never combine agent + extension on
Quarkus.

Validate the result against
[`../schemas/L4-migration-plan.schema.json`](../schemas/L4-migration-plan.schema.json).
