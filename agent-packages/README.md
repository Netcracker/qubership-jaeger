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

| Language        | Frameworks / stacks                     | APM package                    | Status  |
|-----------------|-----------------------------------------|--------------------------------|---------|
| Java            | Spring Boot, Quarkus, Pure (OTel SDK)   | `opentelemetry-tracing-java`   | done    |
| Go              | stdlib, Fiber, platform libs            | `opentelemetry-tracing-go`     | done    |
| Python          | FastAPI, Django, Flask, Pure (OTel SDK) | `opentelemetry-tracing-python` | done    |
| JS / TypeScript | Node, Nest, etc.                        | `opentelemetry-tracing-js`     | planned |

Shared platform pieces (same for all languages):

- Export via **qubership-open-telemetry-collector** → **qubership-jaeger**
- Env vars `TRACING_ENABLED`, `TRACING_HOST`, `TRACING_SAMPLER_PROBABILISTIC`
- Verification: sampling + propagation + end-to-end trace in Jaeger

## Package layout

```text
qubership-jaeger/
├── apm.yml                            # aggregator — installs every package below
└── agent-packages/
    ├── README.md                      # this file
    ├── opentelemetry-tracing-common/    # shared cross-language core
    ├── opentelemetry-tracing-java/        # Java (Spring Boot, Quarkus, Pure)
    ├── opentelemetry-tracing-go/          # Go (stdlib, platform libs)
    ├── opentelemetry-tracing-python/      # Python (FastAPI, Django, Flask, Pure)
    └── opentelemetry-tracing-js/          # planned
```

`opentelemetry-tracing-common` owns shared layers (capability/maturity/transformation/validation), shared schemas,
and the platform tracing contract. Language packages are separate APM units and own language-specific discovery,
detection rules, and recipes.

## Installation

Install the whole program in one step from the repository root (`qubership-jaeger/`), naming your agent:

```shell
apm install -t claude     # or: cursor, copilot, codex, gemini, opencode, windsurf
```

**Pass `-t` — do not rely on auto-detection.** Without it APM scans for a harness marker (`.claude/`,
`CLAUDE.md`, `.cursor/`, `.codex/`, `GEMINI.md`, …) and aborts with "No harness detected" when it finds
none. This repository tracks **no** marker of any kind — every one of them is gitignored — so a fresh
clone has nothing to detect and a bare `apm install` fails. It appears to work only on a checkout where
some agent already left its directory behind, and then it silently deploys for *that* agent rather than
yours. `-t` needs no marker and does not care what previous tooling left lying around.

`apm targets` lists the supported harnesses. Resolution order is `-t` > `targets:` in `apm.yml` >
auto-detect, and `-t` accepts a comma-separated list to deploy for several at once.

Where files land depends on the harness — the packages are identical, only the deployment path differs:

| `-t`     | Rules                       | Skills                       |
|----------|-----------------------------|------------------------------|
| `claude` | `.claude/rules/`            | `.claude/skills/`            |
| `cursor` | `.cursor/rules/*.mdc`       | `.agents/skills/`            |

Contributors on different agents can each run their own `-t` against the same checkout; nothing in the
repository pins a harness, which is deliberate — the agent is a property of the developer, not of the code.

`apm compile` is a **separate concern** and this repository does not need it: it compiles context
primitives (agents, commands, hooks) into `AGENTS.md` / `CLAUDE.md`, and these packages ship none, so it
exits with "no output files". Skills are deployed by `install`, not by `compile`.

Verified against APM CLI 0.19.0.

Root [`apm.yml`](../apm.yml) depends on **every** language package
(`opentelemetry-tracing-java`, `opentelemetry-tracing-go`, `opentelemetry-tracing-python`); each of those
declares `../opentelemetry-tracing-common`, so the shared core arrives transitively — install it separately
and you would get it twice.

Installing everything is deliberate, not convenience. Whoever runs the skill often does not know which
language the target service is written in, and a repository may hold several. With all language packages
present, discovery (L1) identifies the stack itself and the common
[multi-language scope gate](opentelemetry-tracing-common/.apm/skills/opentelemetry-tracing-common/SKILL.md)
asks whether to migrate one target or all of them. A partial install turns that question into a silent
gap — the agent simply cannot see a Go service if only the Java package is installed.

Per-package installs (`apm install` from inside `agent-packages/opentelemetry-tracing-go/`, for example)
still work and remain useful when developing a single package. They are not the way to consume the skill,
and they leave an `apm_modules/` cache inside the package that a later root install reports as an orphaned
package. Delete the package-local `apm_modules/` and `apm.lock.yaml` when you go back to the root install.

A successful root install produces four skills (Java, go, python, common) plus one rule per package, under
the paths listed in the `-t` table above.

You may also see `apm.lock.yaml` and `apm_modules/` (local resolution cache); both are gitignored.
`apm_modules/` holds the packages in their **source** layout, so the cross-package links inside it do not
resolve — see below. It is a cache, not a copy to read.

Restart or reload your agent session (IDE restart, new chat, or rules refresh — per your runtime) so instructions and skills are picked up.

### Cross-package links target the compiled layout

`apm compile` copies package files verbatim — it does **not** rewrite Markdown links. Compilation also
flattens the tree: every package lands as a sibling under `.agents/skills/`, and the `.apm/skills/`
segment disappears. So a link that resolves here in the source tree resolves nowhere once compiled.

Links are therefore written against the **compiled** layout, because that is the copy the agent actually
reads:

```text
.agents/skills/opentelemetry-tracing-java/SKILL.md
  → ../opentelemetry-tracing-common/reference/platform-tracing-guide.md
.agents/skills/opentelemetry-tracing-java/models/5-validation.md
  → ../../opentelemetry-tracing-common/reference/platform-tracing-guide.md
```

The trade-off is that these links do not resolve when browsing `agent-packages/` in an IDE. That is
intentional: a broken link in your editor is a nuisance, while a broken link at runtime silently costs
the agent the platform contract it was told to read first.

When adding a cross-package link, count depth from the package root (`SKILL.md` → `../`, anything in
`models/`, `recipes/`, `reference/`, `schemas/` → `../../`) and never include `.apm/skills/` in the path.
