# Detection rules

The signature catalogue that powers Layer 1 discovery. Match these against
build files, config, env, and code (AST/symbol search). Versions are
deliberately omitted — read them from the repository's `pom.xml`/BOM.

## Dependency signatures

| Coordinates (`groupId:artifactId`)                                         | Bucket | Technology         |
|----------------------------------------------------------------------------|--------|--------------------|
| `io.zipkin.brave:brave*`                                                   | legacy | brave              |
| `io.zipkin.reporter2:*`                                                    | legacy | zipkin             |
| `io.jaegertracing:jaeger-client` / `jaeger-core` / `jaeger-thrift`         | legacy | jaeger-client      |
| `io.opentracing:opentracing-api` / `opentracing-util`                      | legacy | opentracing        |
| `org.springframework.cloud:spring-cloud-starter-sleuth`                    | legacy | sleuth             |
| `org.springframework.cloud:spring-cloud-sleuth-zipkin`                     | legacy | sleuth             |
| `io.quarkus:quarkus-jaeger` / `io.quarkiverse.jaeger:*`                    | legacy | quarkus-jaeger     |
| `io.quarkus:quarkus-smallrye-opentracing` / `io.quarkiverse.opentracing:*` | legacy | opentracing        |
| `io.opentelemetry:opentelemetry-api`                                       | modern | otel-api           |
| `io.opentelemetry:opentelemetry-sdk*`                                      | modern | otel-sdk           |
| `io.opentelemetry:opentelemetry-exporter-otlp`                             | modern | otel-exporter      |
| `io.opentelemetry:opentelemetry-exporter-zipkin`                           | modern | otel-exporter      |
| `io.opentelemetry.instrumentation:opentelemetry-*`                         | modern | otel-sdk           |
| `io.micrometer:micrometer-tracing-bridge-otel`                             | modern | micrometer-bridge  |
| `org.springframework.boot:spring-boot-micrometer-tracing-opentelemetry`    | modern | boot4-otel-starter |
| `org.springframework.boot:spring-boot-starter-opentelemetry`               | modern | boot4-otel-starter |
| `io.micrometer:micrometer-tracing-bridge-brave`                            | legacy | brave              |
| `io.quarkus:quarkus-opentelemetry`                                         | modern | quarkus-otel       |

Aggregate flags:

- `hasOtelApi` = any `otel-api` (directly or via `otel-sdk` / framework bridge).
- `hasOtelSdk` = any `otel-sdk`, `quarkus-otel`, `micrometer-bridge-otel`, or an
  attached `opentelemetry-javaagent`.
- `hasExporter` = any `otel-exporter` **or** an agent (agent bundles exporters).
- `hasLegacy` = any row with bucket `legacy` that is wired, not just transitive.

## Configuration key signatures

| Key / pattern                                                                                                  | Concern                     | Notes                                                                                           |
|----------------------------------------------------------------------------------------------------------------|-----------------------------|-------------------------------------------------------------------------------------------------|
| `OTEL_EXPORTER_OTLP_ENDPOINT`, `otel.exporter.otlp.endpoint`                                                   | export                      | OTLP endpoint                                                                                   |
| `OTEL_EXPORTER_OTLP_PROTOCOL`                                                                                  | export                      | `grpc` / `http/protobuf`                                                                        |
| `management.zipkin.tracing.endpoint`                                                                           | export                      | Zipkin (legacy/Boot)                                                                            |
| `quarkus.otel.exporter.otlp.endpoint`                                                                          | export                      | Quarkus OTLP — expect base URL `:4318` without `/v1/traces`; see `quarkus-platform-contract.md` |
| `quarkus.otel.sdk.disabled` / nested `tracing.sdk.disabled.*`                                                  | export                      | high risk if nested `${TRACING_ENABLED}` toggle; prefer `QUARKUS_OTEL_SDK_DISABLED`             |
| `JAEGER_AGENT_HOST` / `JAEGER_AGENT_PORT` / `JAEGER_ENDPOINT`                                                  | export                      | Jaeger client (legacy)                                                                          |
| `quarkus.jaeger.*` (`endpoint`, `sampler-type`, `propagation`, …)                                              | export/sampling/propagation | retired Quarkus Jaeger extension — legacy `:14268` collector path; migrate to `quarkus.otel.*`  |
| `OTEL_PROPAGATORS`                                                                                             | propagation                 | `tracecontext`, `b3`, `b3multi`, `jaeger`                                                       |
| `management.tracing.propagation.type`                                                                          | propagation                 | `w3c` / `b3`                                                                                    |
| `OTEL_TRACES_SAMPLER` / `OTEL_TRACES_SAMPLER_ARG`                                                              | sampling                    | sampler + ratio (`parentbased_traceidratio` expected; `always_on` is a violation)               |
| `management.tracing.sampling.probability`                                                                      | sampling                    | Boot ratio                                                                                      |
| `management.tracing.enabled` (Boot 3) / `management.tracing.export.enabled` (Boot 4)                           | export                      | Boot 4 rejects Boot 3 key — see `config-migration.md`                                           |
| `management.otlp.tracing.endpoint` (Boot 3) / `management.opentelemetry.tracing.export.otlp.endpoint` (Boot 4) | export                      | Boot 4 rejects Boot 3 key                                                                       |
| `PropertiesMigrationListener` + "incompatible target type" for tracing keys                                    | export                      | Boot 4 config mismatch — OTLP export off until keys + starter fixed                             |
| `quarkus.otel.traces.sampler*`                                                                                 | sampling                    | Quarkus sampler                                                                                 |
| `otel.service.name` / `quarkus.application.name`                                                               | service.name                | must resolve to `${name}-${namespace}`                                                          |
| server instrumentation `excluded-urls` / `known-http-routes`                                                   | endpoint filter             | probe/metrics/actuator exclusion                                                                |
| `TRACING_ENABLED`                                                                                              | export                      | platform master switch (default `false`)                                                        |
| `TRACING_HOST`                                                                                                 | export                      | platform ingress, default `nc-diagnostic-agent`                                                 |
| `TRACING_SAMPLER_PROBABILISTIC`                                                                                | sampling                    | platform ratio (prio 2), `0.01`–`1.0`                                                           |
| `TRACING_SAMPLER_RATELIMITING`                                                                                 | sampling                    | platform rate-limiting sampler (prio 1)                                                         |
| `TRACING_SAMPLER_CONST`                                                                                        | sampling                    | platform const sampler (prio 3), `0`/`1`                                                        |

## Code (AST) symbol signatures

| Symbol                                                                          | Family        | Meaning                  |
|---------------------------------------------------------------------------------|---------------|--------------------------|
| `GlobalOpenTelemetry.getTracer`, `openTelemetry.getTracer`                      | otel          | tracer creation          |
| `spanBuilder(...)`, `startSpan()`, `makeCurrent()`, `end()`                     | otel          | span lifecycle           |
| `TextMapPropagator` `.inject` / `.extract`                                      | otel          | context propagation      |
| `setAttribute(...)`                                                             | otel          | attribute                |
| `recordException(...)`, `setStatus(StatusCode.ERROR)`                           | otel          | error recording          |
| `io.opentracing.Tracer`, `GlobalTracer.get`, `buildSpan().start()`, `.finish()` | opentracing   | legacy spans             |
| `tracer.inject` / `tracer.extract`, `Tags.ERROR`                                | opentracing   | legacy propagation/error |
| `brave.Tracing`, `Tracing.newBuilder`, `span.tag(...)`                          | brave         | legacy spans/attrs       |
| `io.jaegertracing.*`, `Configuration.fromEnv()`                                 | jaeger-client | legacy Jaeger SDK        |

## Instrumentation-mode signatures

| Evidence                                                               | Mode signal |
|------------------------------------------------------------------------|-------------|
| `-javaagent:opentelemetry-javaagent.jar` in entrypoint/Dockerfile      | auto        |
| `JAVA_TOOL_OPTIONS` containing `opentelemetry-javaagent`               | auto        |
| OTel instrumentation starter modules without manual spans              | auto        |
| Manual `getTracer()` + `spanBuilder()` + `end()` in app code, no agent | manual      |
| Agent **and** manual spans together                                    | mixed       |
| None of the above                                                      | none        |

## Async-boundary signatures

| Symbol                                                            | Boundary type              |
|-------------------------------------------------------------------|----------------------------|
| `KafkaProducer`, `ProducerRecord`, `KafkaTemplate.send`           | kafka-producer             |
| `@KafkaListener`, `ConsumerRecord`, `KafkaConsumer.poll`          | kafka-consumer             |
| `ExecutorService`, `.submit(`, `.execute(`                        | executor                   |
| `CompletableFuture.supplyAsync`, `thenApplyAsync`, `thenRunAsync` | completable-future         |
| `Mono`, `Flux`, `publishOn`, `subscribeOn`, `contextWrite`        | reactor                    |
| `@Incoming`, `@Outgoing`, Mutiny `Uni`/`Multi`                    | quarkus-reactive-messaging |

A boundary is a **context-loss candidate** when no nearby context wrapper is
found (`Context.taskWrapping`, `ContextSnapshot`, OTel Kafka instrumentation,
`contextWrite(...)`). Set `contextWrapper: false` in that case.

## Additional Java framework signals (best-effort)

These frameworks are supported in best-effort mode. If detected, keep using
generic OTel discovery/capability/validation and emit framework evidence in
the discovery result.

| Signal | Framework |
| --- | --- |
| `io.micronaut:micronaut-*` | Micronaut |
| `io.helidon.*` | Helidon |
| Eclipse Vert.x stack | Vert.x |
| `jakarta.ws.rs`, `jakarta.servlet` | Jakarta EE / Servlet container |
| `io.dropwizard:*` | Dropwizard |

Typical Maven coordinates for Vert.x (grep `pom.xml` / Gradle files): use the
canonical Eclipse Vert.x group and module artifact names from upstream docs.

## Platform-contract signatures

These feed the contract checks (see umbrella
[`platform-tracing-guide.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md)).

| Signal                                                                                                                                 | Maps to                         | Compliant when                                   |
|----------------------------------------------------------------------------------------------------------------------------------------|---------------------------------|--------------------------------------------------|
| `otel.service.name=${...}-${NAMESPACE...}` / `quarkus.application.name=${...}-${NAMESPACE...}`                                         | `serviceName.includesNamespace` | value composes name + namespace                  |
| Downward API `fieldRef: metadata.namespace`, Helm `.Release.Namespace`, file `/var/run/secrets/kubernetes.io/serviceaccount/namespace` | namespace source                | namespace is injected/read                       |
| `opentelemetry-extension-trace-propagators` dependency                                                                                 | B3 capability                   | present when `b3`/`b3multi` configured           |
| `opentelemetry-log4j-context-data-2.17-autoconfigure` (log4j), `opentelemetry-logback-mdc-1.0` (logback)                               | `logging.correlationDep`        | present when MDC trace fields used               |
| log pattern `%X{trace_id}` / `%X{span_id}` (Spring) or `%X{traceId}` / `%X{spanId}` (Quarkus), or literal `[traceId=...][spanId=...]`  | `logging.traceFieldsInPattern`  | pattern carries both IDs                         |
| excluded URLs include `/health*`, `/livez`, `/readiness`, `/metrics`, `/actuator*`, `/q/*`                                             | `endpointFilter`                | probe/metrics/management excluded                |
| `io.jaegertracing:*`, `io.opentracing:*`                                                                                               | retired libs                    | absent — these are end-of-life migration targets |

When a contract signal is absent, mark the corresponding capability facet
`FAILED` (it is mandatory) rather than `UNKNOWN`, unless the file that would
carry it could not be inspected.
