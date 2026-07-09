# Layer 4 — Transformation (Go)

Shared plan structure, algorithm, and section numbering (§4.1–§4.5):
[`opentelemetry-tracing-umbrella/models/4-transformation.md`](../../../../../opentelemetry-tracing-umbrella/.apm/skills/opentelemetry-tracing-umbrella/models/4-transformation.md).

Run the **Go gate below before §4.1**. Then fill §4.1–§4.4 from recipes:

| Section                      | Recipe                                                                                                                                        |
|------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
| §4.1 `dependencyMigration`   | [`../recipes/dependency-migration.md`](../recipes/dependency-migration.md)                                                                    |
| §4.2 `configMigration`       | [`../recipes/config-migration.md`](../recipes/config-migration.md) + [`../recipes/logging-correlation.md`](../recipes/logging-correlation.md) |
| §4.3 `codeMigration`         | [`../recipes/code-migration.md`](../recipes/code-migration.md)                                                                                |
| §4.4 `asyncContextMigration` | [`../recipes/async-context-migration.md`](../recipes/async-context-migration.md)                                                              |

## Step 0 — Framework stack decision (mandatory)

**Framework stack** = how the service serves HTTP (from L1 → `service.framework` in
`discovery-result.json`): Fiber with a server wrapper, stdlib `net/http`, Gin, Echo,
etc. — not programming language and not “one repository = one stack” by default.

Read `discovery-result.service.framework` and pick exactly one migration path.
Do not emit §4.1 or §4.2 rows before this is fixed.

| `service.framework`           | Target instrumentation                                                      | Config surface           |
|-------------------------------|-----------------------------------------------------------------------------|--------------------------|
| `cloudcore-fiber`             | Fiber + platform HTTP wrapper → OTLP via `TRACING_*` / wrapper `WithTracer` | env + Helm + app config  |
| `net-http`                    | `go.opentelemetry.io/otel/sdk` + OTLP HTTP exporter + B3 propagator         | env + programmatic setup |
| `gin` / `echo` / other router | router middleware + SDK/OTLP exporter                                       | env + middleware setup   |
| `pure-go`                     | SDK + OTLP exporter (no router-specific middleware)                         | env + programmatic setup |
| `unknown`                     | conservative SDK path; record assumptions in `gaps`                         | env                      |

Pull versions from `go.mod`; never pin in the plan.

## Step 0b — Instrumentation-mechanism guardrails (mandatory)

After the framework stack is chosen, validate mechanism:

- end with one active tracing stack;
- remove Zipkin/OpenTracing/Jaeger client as active exporters;
- preserve required platform contract (`TRACING_*`, OTLP, propagation, sampling);
- if the service uses a **vendor/platform tracing wrapper** (`NewZipkinTracer`,
  `WithTracer`, …), migrate wrapper configuration first before custom
  instrumentation — see `dependency-migration.md` / `code-migration.md`.

Validate result against
[`../schemas/L4-migration-plan.schema.json`](../schemas/L4-migration-plan.schema.json).
