# Layer 1 — Discovery

**Goal:** enumerate every existing element of the tracing implementation.
Discovery reports *what is present*, not whether it works (that is Layer 2).

- **Input:** repository root (source, build files, config, deployment, Helm/k8s).
- **Output:** `discovery-result.json` → [`../schemas/L1-discovery-result.schema.json`](../schemas/L1-discovery-result.schema.json).
- **Detection signatures:** [`../reference/detection-rules.md`](../reference/detection-rules.md).

Discovery has six sub-models. Run all six; if evidence is missing, still emit
the required JSON object and set its inspected fields to `unknown` (or an empty
array where the schema expects an array). Record the reason in `gaps`; do not
omit required sections.

## 1.1 Dependency discovery

Answer: *which tracing libraries are present, and in what role?*

**Inputs:** `pom.xml`, parent POMs, BOM imports, `build.gradle(.kts)`,
`gradle.lockfile`, `dependencies` blocks, and — when resolvable — the full
dependency tree (`mvn dependency:tree`, `gradle dependencies`).

Framework detection baseline:

- first-class: Spring Boot, Quarkus, Pure Java
- best-effort: Micronaut, Helidon, Vert.x, Jakarta EE/Servlet containers, Dropwizard

For best-effort frameworks, detect with generic OTel signatures and emit
`framework="unknown"` + evidence notes if a confident classification is not possible.

**Algorithm:**

1. Collect direct dependencies from build files.
2. Resolve the dependency tree when tooling is available; otherwise mark
   transitive coverage `partial` and record it under `gaps`.
3. For each tracing-related artifact capture: `groupId:artifactId`,
   `version` (or "managed"), and `scope` (compile/runtime/test/provided).
4. Classify each against the catalogue in `detection-rules.md`.

**Classification buckets:**

- **Legacy** — Brave (`io.zipkin.brave:*`), Zipkin reporter
  (`io.zipkin.reporter2:*`), Jaeger client (`io.jaegertracing:*`),
  OpenTracing (`io.opentracing:*`), Spring Cloud Sleuth
  (`org.springframework.cloud:spring-cloud-starter-sleuth`).
- **Modern** — OpenTelemetry API (`io.opentelemetry:opentelemetry-api`),
  SDK (`opentelemetry-sdk`), exporters (`opentelemetry-exporter-otlp`,
  `-zipkin`), Micrometer Tracing bridge
  (`io.micrometer:micrometer-tracing-bridge-otel`), Spring Boot OTel starter
  (`org.springframework.boot:spring-boot-micrometer-tracing-opentelemetry` /
  `spring-boot-starter-opentelemetry`), Quarkus OTel
  (`io.quarkus:quarkus-opentelemetry`).

**Output:** the `dependencyProfile` object — one entry per tracing
artifact with its bucket, plus aggregate booleans (`hasOtelApi`,
`hasOtelSdk`, `hasExporter`, `hasLegacy`).

## 1.2 Configuration discovery

Answer: *where is tracing configured, and how?*

**Inputs (Java):** `application.properties`, `application.yml(.yaml)`,
profile variants, environment variables in `Dockerfile`/compose, JVM args
(`JAVA_TOOL_OPTIONS`, `-D...`), Helm `values.yaml`, k8s `Deployment`/
`StatefulSet` env, ConfigMaps.

Split the findings into three concerns:

### Export configuration

Determine: exporter type (OTLP / Zipkin / Jaeger / none), endpoint, protocol
(gRPC / http-protobuf / thrift), and whether it points at OTeC or the Jaeger
collector (cross-check [`platform-tracing-guide.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md) §Export).
Keys to read: `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_EXPORTER_OTLP_PROTOCOL`,
`otel.exporter.otlp.*`, `management.zipkin.tracing.endpoint`,
`quarkus.otel.exporter.otlp.endpoint`, and platform `TRACING_HOST`.

### Context-propagation configuration

Determine the wire format(s) configured:

- **W3C Trace Context** — `traceparent` / `tracestate`
  (`OTEL_PROPAGATORS=tracecontext`, `management.tracing.propagation.type=w3c`).
- **B3** — `X-B3-TraceId` / `X-B3-SpanId` (`OTEL_PROPAGATORS=b3` / `b3multi`,
  `management.tracing.propagation.type=b3`).

Then record per-component support as `OK` / `FAILED` / `unknown` (the
detailed verdict is Layer 2; here just note which components are wired):

```text
HTTP:  OK
Kafka: FAILED   (no header inject/extract found)
```

### Sampling configuration

Determine: is a sampler configured, its type (always_on / always_off /
traceidratio / parentbased_*), its ratio, and whether the ratio is consistent
across services you can see. Keys: `OTEL_TRACES_SAMPLER`,
`OTEL_TRACES_SAMPLER_ARG`, `management.tracing.sampling.probability`,
`quarkus.otel.traces.sampler*`, platform `TRACING_SAMPLER_PROBABILISTIC`.

**Output:** the `configuration` object (`export`, `propagation`, `sampling`).

## 1.3 API discovery (AST)

Answer: *how is the tracing API used in code?*

**Inputs:** `src/main/java/**/*.java` (and Kotlin if present). Prefer AST
parsing; fall back to symbol search when AST tooling is unavailable, and
record the degraded mode under `gaps`.

**Search for:**

- Tracer creation — `GlobalOpenTelemetry.getTracer`, `openTelemetry.getTracer`,
  `GlobalTracer.get` (OpenTracing), `Tracing.newBuilder` (Brave).
- Span creation / lifecycle — `spanBuilder(...)`, `startSpan()`, `makeCurrent()`,
  `end()`; OpenTracing `buildSpan().start()`, `.finish()`.
- Context extraction / injection — `TextMapPropagator.extract/inject`,
  `tracer.extract/inject` (OpenTracing), Brave `Extractor/Injector`.
- Attributes / tags — `setAttribute(...)`, OpenTracing/Brave `tag(...)`.
- Exception recording — `recordException(...)`, `setStatus(StatusCode.ERROR)`,
  OpenTracing error tag (`Tags.ERROR`).

For each finding record API family (`otel` / `opentracing` / `brave`), symbol,
file, and line.

**Output:** the `apiUsage` array plus `apiFamilies` summary.

## 1.4 Instrumentation discovery

Answer: *how is instrumentation produced — automatically, manually, or both?*

**Classification (`instrumentation.mode` values):**

- `auto` — `-javaagent:opentelemetry-javaagent.jar`, `opentelemetry-javaagent`
  on the image/`JAVA_TOOL_OPTIONS`, OTel instrumentation starter modules, **and**
  no manual span creation in app code.
- `manual` — explicit `GlobalOpenTelemetry.getTracer()` / `spanBuilder()` /
  `span.end()` in app code, no agent.
- `mixed` — agent **and** manual span creation both present.
- `none` — no automatic instrumentation evidence and no manual span API usage.

**Inputs:** Dockerfile / entrypoint, `JAVA_TOOL_OPTIONS`, k8s env, build
files (instrumentation starters), plus the `apiUsage` result from 1.3.

**Output:** `instrumentation.mode` ∈ {`auto`,`manual`,`mixed`,`none`} with the
evidence that justified it.

## 1.5 Async-boundary discovery

Answer: *where can context be lost?*

**Search for (Java):**

- **Kafka** — `KafkaProducer`, `ProducerRecord`, `@KafkaListener`,
  `ConsumerRecord`, Spring `KafkaTemplate`, Quarkus Reactive Messaging
  `@Incoming`/`@Outgoing`.
- **ExecutorService / thread pools** — `ExecutorService`, `submit(`, `execute(`.
- **CompletableFuture** — `CompletableFuture.supplyAsync`, `thenApplyAsync`.
- **Reactor** — `Mono`, `Flux`, `publishOn`, `subscribeOn`, `contextWrite`.
- **Quarkus Reactive Messaging** — Mutiny `Uni`/`Multi` handoffs.

For each, record the boundary type, file/line, and whether any context-propagation wrapper is present nearby
(`Context.taskWrapping`, `ContextSnapshot`, OTel Kafka instrumentation). Absence ⇒ candidate context-loss point for
Layer 2.

**Output:** the `asyncBoundaries` array.

## 1.6 Platform-contract discovery

Answer: *does the service follow the platform tracing contract?* These facts are mandatory for the Qubership/NC
platform — collect them so Layers 2 and 5 can verify them. Source of truth:
[`platform-tracing-guide.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/reference/platform-tracing-guide.md);
signatures in [`../reference/detection-rules.md`](../reference/detection-rules.md)
(§Platform-contract signatures).

Collect:

- **service.name namespace** — does `otel.service.name` /
  `quarkus.application.name` resolve to `${name}-${namespace}`, and is the
  namespace injected (Downward API / Helm / SA file)?
- **Sampler tier** — which of `TRACING_SAMPLER_RATELIMITING` /
  `_PROBABILISTIC` / `_CONST` is wired, and is the OTel sampler
  `parentbased_traceidratio` (not `always_on`)?
- **Propagation standard** — is `b3multi` configured, and is
  `opentelemetry-extension-trace-propagators` present?
- **Endpoint filtering** — are probe/metrics/management URLs excluded?
- **Logging correlation** — is `traceId`/`spanId` in the log pattern, and is
  the MDC dependency (`opentelemetry-log4j-context-data-*` /
  `opentelemetry-logback-mdc-*`) present? (CloudCore libs may supply this.)
- **Export shape** — OTLP `http/protobuf` to
  `http://${TRACING_HOST}:4318/v1/traces`; `TRACING_HOST` default
  `nc-diagnostic-agent`.

**Output:** the `platformContract` object (required on every `discovery-result.json`).

## Output format

Emit one JSON object validated against
[`../schemas/L1-discovery-result.schema.json`](../schemas/L1-discovery-result.schema.json):

```json
{
  "service": { "name": "order-service", "framework": "spring-boot" },
  "dependencyProfile": {
    "hasOtelApi": false, "hasOtelSdk": false, "hasExporter": false, "hasLegacy": true,
    "artifacts": [
      {
        "coordinates": "io.zipkin.brave:brave",
        "version": "5.x",
        "scope": "compile",
        "bucket": "legacy",
        "technology": "brave"
      }
    ]
  },
  "configuration": {
    "export": { "exporter": "zipkin", "endpoint": "http://zipkin:9411", "protocol": "http-thrift", "targetGuess": "legacy-zipkin" },
    "propagation": { "formats": ["b3"], "components": { "http": "OK", "kafka": "FAILED" } },
    "sampling": { "configured": true, "type": "probabilistic", "ratio": 1.0, "consistentAcrossServices": "unknown" }
  },
  "apiUsage": [
    { "family": "brave", "symbol": "Tracing.newBuilder", "file": "src/main/java/.../TracingConfig.java", "line": 24 }
  ],
  "apiFamilies": ["brave"],
  "instrumentation": { "mode": "manual", "evidence": ["brave Tracing bean", "no -javaagent"] },
  "asyncBoundaries": [
    { "type": "kafka-producer", "file": "src/main/java/.../OrderPublisher.java", "line": 41, "contextWrapper": false }
  ],
  "platformContract": {
    "serviceName": { "value": "order-service", "includesNamespace": false, "namespaceSource": "none" },
    "samplerTier": "none",
    "samplerType": "unknown",
    "propagationStandard": "b3",
    "hasB3PropagatorExtension": false,
    "endpointFilter": { "configured": false, "excluded": [] },
    "logging": { "traceFieldsInPattern": false, "correlationDep": "none" },
    "export": { "protocol": "unknown", "endpointPath": null, "tracingHost": "zipkin" }
  },
  "gaps": ["dependency tree not resolved (offline)"]
}
```

## User-facing brief (mandatory)

After emitting `discovery-result.json`, post an **L1 Discovery brief** in the
agent chat (5–10 bullets). Template:

```markdown
### L1 Discovery — <service-name>
- **Framework:** …
- **Dependencies:** hasOtelSdk=…, hasLegacy=…, key artifacts: …
- **Config:** export=…, propagation=…, sampling=…
- **Instrumentation:** mode=…
- **Async boundaries:** … (or none)
- **Platform guide:** … (plain language only — e.g. missing trace IDs in logs;
  wrong export endpoint — or "aligned with platform tracing guide")
- **Gaps:** …
```

Record full contract evidence in `discovery-result.platformContract` (JSON) for
L2 — do **not** mirror raw facet names or enum verdicts in this brief.

Do not proceed to L2 until the brief is posted. Full rules: [`../SKILL.md`](../SKILL.md) §3.1.
