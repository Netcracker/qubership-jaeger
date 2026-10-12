# OpenTelemetry tracing skills (Qubership)

APM packages for migrating Qubership services to **OpenTelemetry SDK** tracing and
fixing broken distributed traces across the platform.

## Problem

| Issue                                      | Skill response                           |
| ------------------------------------------ | ---------------------------------------- |
| Components without tracing                 | Detect stack → add OTel SDK + export     |
| Broken context propagation                 | Mandatory propagator audit in every task |
| Async/Kafka handlers lose context          | Async/messaging module per language      |
| Legacy SDKs (Brave, Jaeger client, Sleuth) | Migration module per language            |
| Wrong sampling in prod                     | Mandatory sampling audit in verification |

## Target languages and frameworks

| Language   | Frameworks / stacks                     | APM package                    |
| ---------- | --------------------------------------- | ------------------------------ |
| Java       | Spring Boot, Quarkus, Pure (OTel SDK)   | `opentelemetry-tracing-java`   |
| Go         | stdlib, Fiber, platform libs            | `opentelemetry-tracing-go`     |
| Python     | FastAPI, Django, Flask, Pure (OTel SDK) | `opentelemetry-tracing-python` |
| TypeScript | Express, Fastify, NestJS, Pure (Node)   | `opentelemetry-tracing-ts`     |

Shared platform pieces (same for all languages):

- Export via **qubership-open-telemetry-collector** → **qubership-jaeger**
- Env vars `TRACING_ENABLED`, `TRACING_HOST`, `TRACING_SAMPLER_PROBABILISTIC`
- Verification: sampling + propagation + end-to-end trace in Jaeger

## Package layout

```text
qubership-jaeger/
└── agent-packages/
    └── otel_sdk_migration/
        ├── apm.yml                             # aggregator — installs every package below
        ├── README.md                           # this file
        ├── opentelemetry-tracing-common/       # shared cross-language core
        ├── opentelemetry-tracing-java/         # Java (Spring Boot, Quarkus, Pure)
        ├── opentelemetry-tracing-go/           # Go (stdlib, platform libs)
        ├── opentelemetry-tracing-python/       # Python (FastAPI, Django, Flask, Pure)
        └── opentelemetry-tracing-ts/           # TypeScript/Node (Express, Fastify, NestJS, Pure)
```

`opentelemetry-tracing-common` owns shared layers (capability/maturity/transformation/validation), shared schemas,
and the platform tracing contract. Language packages are separate APM units and own language-specific discovery,
detection rules, and recipes.

## Installation

Install the whole program in one step from this directory
(`agent-packages/otel_sdk_migration/`), naming your agent:

```shell
apm install -t claude     # or: cursor, copilot, codex, gemini, opencode, windsurf
```

**Pass `-t`.** Auto-detection needs a harness marker (`.claude/`, `CLAUDE.md`, `.cursor/`, …) and this repository
tracks none — they are all gitignored. A bare `apm install` therefore either aborts with "No harness detected" or
silently deploys for whichever agent last left a directory behind. `apm targets` lists the supported values; `-t`
accepts a comma-separated list.

### Which entry point to use

Bulk — the aggregator [`apm.yml`](apm.yml) — is the default. Whoever runs the skill often does not know which language
the target service is written in, and a repository may hold several: with every language package present, discovery
(L1) identifies the stack itself and the
common [multi-language scope gate](opentelemetry-tracing-common/.apm/skills/opentelemetry-tracing-common/SKILL.md)
asks whether to migrate one target or all of them. A single-language install trades that away — the agent cannot see a
Go service if only the Java package is installed, and the gap is silent. Take it when the target language is already
known and the smaller agent context is worth it.

Never add `opentelemetry-tracing-common` yourself: every language package declares it, so the shared core arrives
transitively either way.

Operational notes:

- dependencies are repository references (`Netcracker/qubership-jaeger/agent-packages/otel_sdk_migration/<package>`)
  resolved through the APM cache, so an install deploys the pushed ref rather than your working tree;
- a per-package install leaves an `apm_modules/` cache inside that package, which a later aggregator install reports
  as an orphaned package. Delete the package-local `apm_modules/` and `apm.lock.yaml` when going back to the
  aggregator.

### Cross-package links target the compiled layout

Deployment copies package files verbatim and flattens the tree: every package lands as a sibling under the harness
skills directory, and the `.apm/skills/` segment disappears. Links are written against that deployed layout, so they
do not resolve while browsing the source tree in an IDE. That is deliberate — a link the agent cannot follow at
runtime silently costs it the platform contract it was told to read first.

When adding one, count depth from the package root (`SKILL.md` → `../`, anything in `models/`, `recipes/`,
`reference/`, `schemas/` → `../../`) and never include `.apm/skills/` in the path.
