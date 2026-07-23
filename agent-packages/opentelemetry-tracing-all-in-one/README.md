# opentelemetry-tracing-all-in-one

Aggregator package: installs **all** Qubership OpenTelemetry tracing skills in one
step — the Java, Go, and Python language packages plus the shared core they
depend on.

## Why this package exists

Whoever runs the tracing skill often does **not** know which language the target
service is written in — and a single repository may hold services in several
languages. Installing this one package gives the agent every language's
discovery / detection / recipe set at once, so it can audit and migrate tracing
in any service and pick the right language path per service, without the user
choosing a language up front.

Install one thing, cover every supported language.

## What it pulls in

- [`opentelemetry-tracing-java`](../opentelemetry-tracing-java) — Spring Boot, Quarkus, Pure (OTel SDK)
- [`opentelemetry-tracing-go`](../opentelemetry-tracing-go) — stdlib, platform libs
- [`opentelemetry-tracing-python`](../opentelemetry-tracing-python) — FastAPI, Django, Flask, Pure (OTel SDK)
- shared core (`opentelemetry-tracing-common`) — declared by each language
  package, so it arrives transitively and APM resolves it **once** (do not add it
  separately or you get it twice)

## Which entry point to use

| You want to…                                                                  | Use                                   |
|-------------------------------------------------------------------------------|---------------------------------------|
| Install everything from *inside this repo*                                    | root [`apm.yml`](../../apm.yml)       |
| Reference the whole suite as **one dependency** from another repo (or by path) | this package                          |
| Install a single, known language                                              | that language package directly        |

The difference from the root `apm.yml`: the root uses in-repo paths
(`./agent-packages/...`) and only works from the repository root; this package
uses sibling paths (`../...`), so it can be referenced as a normal APM dependency
from anywhere.

## Install

```shell
apm install -t <target>
```

Run from a repo whose `apm.yml` depends on this package, or point an install at
this package directly. The shared core is resolved automatically.
