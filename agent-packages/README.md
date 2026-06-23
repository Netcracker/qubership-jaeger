# OpenTelemetry tracing skills (Qubership)

APM packages for migrating Qubership services to **OpenTelemetry SDK** tracing and
fixing broken distributed traces across the platform.

## Problem

| Issue                                      | Skill response                           |
|--------------------------------------------|------------------------------------------|
| Components without tracing                 | Detect stack → add OTel SDK + export     |
| Broken context propagation                 | Mandatory propagator audit in every task |
| Async/Kafka handlers lose context          | Async/messaging module per language      |
| Legacy SDKs (Brave, Jaeger client, Sleuth) | Migration module per language            |
| Wrong sampling in prod                     | Mandatory sampling audit in verification |

## Target languages and frameworks

| Language        | Frameworks / stacks                   | APM package                    | Status  |
|-----------------|---------------------------------------|--------------------------------|---------|
| Java            | Spring Boot, Quarkus, Pure (OTel SDK) | `opentelemetry-tracing-java`   | done    |
| Go              | stdlib, Fiber, platform libs          | `opentelemetry-tracing-go`     | planned |
| Python          | TBD (FastAPI, Django, etc.)           | `opentelemetry-tracing-python` | planned |
| JS / TypeScript | Node, Nest, etc.                      | `opentelemetry-tracing-js`     | planned |

Shared platform pieces (same for all languages):

- Export via **qubership-open-telemetry-collector** → **qubership-jaeger**
- Env vars `TRACING_ENABLED`, `TRACING_HOST`, `TRACING_SAMPLER_PROBABILISTIC`
- Verification: sampling + propagation + end-to-end trace in Jaeger

## Package layout

```text
agent-packages/
├── README.md                          # this file
├── opentelemetry-tracing-umbrella/    # shared cross-language core
├── opentelemetry-tracing-java/        # Java (Spring Boot, Quarkus, Pure)
├── opentelemetry-tracing-go/          # planned
├── opentelemetry-tracing-python/      # planned
└── opentelemetry-tracing-js/          # planned
```

`opentelemetry-tracing-umbrella` owns shared layers (capability/maturity/transformation/validation), shared schemas,
and the platform tracing contract. Language packages are separate APM units and own language-specific discovery,
detection rules, and recipes.

## Installation

From the repository root (`qubership-jaeger/`), install and compile for your agent target:

```shell
apm install -t <target>
apm compile -t <target>
```

Use the compile target your APM setup expects (for example `cursor`, `claude`, or another supported runtime).

Root `apm.yml` depends on `./agent-packages/opentelemetry-tracing-java`.
That package transitively pulls `../opentelemetry-tracing-umbrella` (declared in the Java package `apm.yml`).

Generated files depend on `<target>`. Examples:

| Target family                     | Rules / instructions                        | Skills                                            |
|-----------------------------------|---------------------------------------------|---------------------------------------------------|
| Cursor                            | `.cursor/rules/opentelemetry-tracing-*.mdc` | `.agents/skills/opentelemetry-tracing-*/`         |
| Claude Code / Codex-style compile | `CLAUDE.md` / `AGENTS.md`                   | target-native skill paths under `.agents/skills/` |

You may also see `apm.lock.yaml` and `apm_modules/` (local resolution cache); both are gitignored at the repo root.

Restart or reload your agent session (IDE restart, new chat, or rules refresh — per your runtime) so instructions and skills are picked up.

## Sources

| Topic                     | Repository                           |
|---------------------------|--------------------------------------|
| Jaeger Helm, ports        | `qubership-jaeger` (this repo)       |
| OTeC ingress, `TRACING_*` | `qubership-open-telemetry-collector` |
| Java libs                 | `qubership-core-java-libs`           |
| Go libs                   | `qubership-core-lib-go-*` (to clone) |
