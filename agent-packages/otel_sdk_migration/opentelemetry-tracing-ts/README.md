# opentelemetry-tracing-ts

APM skill for **TypeScript / Node** services (Express, Fastify, NestJS, pure Node
OTel SDK): a five-layer pipeline that audits an unknown service's tracing, scores
maturity, and produces an OpenTelemetry migration and validation plan.

Part of the multi-language tracing program — see [`../README.md`](../README.md).

## Scope: TypeScript

This package targets **TypeScript** services and aims to cover them fully. It is
**not** a JavaScript-language track. JS files (`.js`, `.mjs`, `.cjs`) are scanned
only as an unavoidable consequence of TypeScript: TS compiles to JavaScript, the
deployed/bundled artifact and the tracing bootstrap are JS, and dependencies are
shared — so the compiled output, the bundle, and `package.json` must be read to
cover TypeScript at all (the load-order, bundling, and export pitfalls live in
those JS artifacts). Plain-JavaScript services are not a maintained target of this
package.

## Architecture

The skill is orchestrated by
[`SKILL.md`](.apm/skills/opentelemetry-tracing-ts/SKILL.md). Each layer reads the
previous artifact and emits the next:

| Layer             | File                            | Output                                          |
| ----------------- | ------------------------------- | ----------------------------------------------- |
| L1 Discovery      | `models/1-discovery.md`         | `discovery-result`                              |
| L2 Capability     | common `models/2-capability.md` | `capability-result`                             |
| L3 Maturity       | common `models/3-maturity.md`   | `maturity-result`                               |
| L4 Transformation | `models/4-transformation.md`    | shared plan + TS framework/mechanism gate       |
| L5 Validation     | `models/5-validation.md`        | shared tiers + TS build/runtime execution rules |

## Supporting material

The file index — schemas, detection rules, framework coverage, recipes, and which pieces come from common — is
[`SKILL.md`](.apm/skills/opentelemetry-tracing-ts/SKILL.md) §6, the copy the agent reads and the only place they are
listed. Shared core: [`../opentelemetry-tracing-common/`](../opentelemetry-tracing-common/).

## Source-of-truth policy

- Qubership platform contract comes from common
  [`platform-tracing-guide.md`](../opentelemetry-tracing-common/.apm/skills/opentelemetry-tracing-common/reference/platform-tracing-guide.md)
  (contracted `TRACING_*`, OTLP format, B3/B3Multi, sampling, namespace in `service.name`,
  endpoint filtering, and log correlation).
- TypeScript/Node-specific detection rules and recipes live in this package.

## Local check

From this package directory, or from `agent-packages/otel_sdk_migration/` when installing the whole program:

```shell
apm install -t claude
```
