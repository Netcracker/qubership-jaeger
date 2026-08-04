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

First-class and best-effort framework families, and the `unknown` fallback:
[`../reference/framework-coverage.md`](../reference/framework-coverage.md).

**Algorithm:**

1. Collect direct dependencies from build files.
2. Resolve the dependency tree when tooling is available; otherwise mark
   transitive coverage `partial` and record it under `gaps`.
3. For each tracing-related artifact capture: `groupId:artifactId`,
   `version` (or "managed"), and `scope` (compile/runtime/test/provided).
4. Classify each into its bucket and set the aggregate flags — catalogue and
   bucket assignments:
   [`../reference/detection-rules.md`](../reference/detection-rules.md)
   §Dependency signatures.

**Output:** the `dependencyProfile` object — one entry per tracing artifact with
its bucket, plus the aggregate booleans.

## 1.2 Configuration discovery

Answer: *where is tracing configured, and how?*

**Inputs (Java):** `application.properties`, `application.yml(.yaml)`,
profile variants, environment variables in `Dockerfile`/compose, JVM args
(`JAVA_TOOL_OPTIONS`, `-D...`), Helm `values.yaml`, k8s `Deployment`/
`StatefulSet` env, ConfigMaps.

Split the findings into three concerns. The keys to read for each are
[`../reference/detection-rules.md`](../reference/detection-rules.md)
§Configuration key signatures, which also carries the `configScope` each surface
implies (Quarkus propagators are build-time; Boot and Pure Java are runtime).

### Export configuration

Determine exporter type (OTLP / Zipkin / Jaeger / none), endpoint, protocol, and
whether it points at the platform proxy or straight at a collector — cross-check
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Export.

### Context-propagation configuration

Record the wire formats as **two separate sets** — `inject` and `extract` — in the
order written, and note the framework's winner end. Why the directions differ and
which end wins per stack:
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§Propagation.

**Record the effective default when no key is present** and set
`propagation.fromFrameworkDefault: true` — an unconfigured Spring Boot service
still injects and extracts (guide §Framework defaults are asymmetric). "Not
configured" is never "no propagation".

Then record per-component support as `OK` / `FAILED` / `unknown` (the
detailed verdict is Layer 2; here just note which components are wired):

```text
HTTP:  OK
Kafka: FAILED   (no header inject/extract found)
```

### Sampling configuration

Determine whether a sampler is configured, its type and ratio, and whether the
ratio is consistent across the services in view.

**Output:** the `configuration` object (`export`, `propagation`, `sampling`).

## 1.3 API discovery (AST)

Answer: *how is the tracing API used in code?*

**Inputs:** `src/main/java/**/*.java` (and Kotlin if present). Prefer AST
parsing; fall back to symbol search when AST tooling is unavailable, and
record the degraded mode under `gaps`.

Search for the OTel, OpenTracing, and Brave symbols catalogued in
[`../reference/detection-rules.md`](../reference/detection-rules.md) §Code (AST)
symbol signatures. For each finding record API family (`otel` / `opentracing` /
`brave`), symbol, file, and line.

**Output:** the `apiUsage` array plus `apiFamilies` summary.

## 1.4 Instrumentation discovery

Answer: *how is instrumentation produced — automatically, manually, or both?*

Classify `instrumentation.mode` (`auto` / `manual` / `mixed` / `none`) from
[`../reference/detection-rules.md`](../reference/detection-rules.md)
§Instrumentation-mode signatures.

**Inputs:** Dockerfile / entrypoint, `JAVA_TOOL_OPTIONS`, k8s env, build
files (instrumentation starters), plus the `apiUsage` result from 1.3.

**Output:** `instrumentation.mode` ∈ {`auto`,`manual`,`mixed`,`none`} with the
evidence that justified it.

## 1.5 Async-boundary discovery

Answer: *where can context be lost?*

Boundary catalogue and the context-wrapper rule:
[`../reference/detection-rules.md`](../reference/detection-rules.md)
§Async-boundary signatures. For each hit record the boundary type, file/line, and
`contextWrapper`.

**Output:** the `asyncBoundaries` array.

## 1.6 Platform-contract discovery

Answer: *does the service follow the platform tracing contract?* These facts are mandatory for the Qubership/NC
platform — collect them so Layers 2 and 5 can verify them. Source of truth:
[`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md);
signatures in [`../reference/detection-rules.md`](../reference/detection-rules.md)
(§Platform-contract signatures).

Resolve every facet from the Java signals in the §Platform-contract signatures
table. Two readings are L1's own: record the **sampler tier** (which of the three
`TRACING_SAMPLER_*` switches is wired) separately from the OTel sampler class, and
record propagation as the **effective** value including framework defaults, not
just explicit keys.

**Output:** the `platformContract` object (required on every `discovery-result.json`).

## Output

One `discovery-result` object in the shape of
[`../schemas/L1-discovery-result.schema.json`](../schemas/L1-discovery-result.schema.json), including the
required `platformContract` block. It is in-session data, not a file — common
[`SKILL.md`](../../opentelemetry-tracing-common/SKILL.md) §Where the artifacts live.

Then post the **L1 Discovery brief** — content and rules in common
[`reference/user-briefs.md`](../../opentelemetry-tracing-common/reference/user-briefs.md), Java additions in
[`../SKILL.md`](../SKILL.md) §3.1. Record full contract evidence in the artifact; do not mirror facet names or
verdict tokens in the brief. Do not proceed to L2 until the brief is posted.
