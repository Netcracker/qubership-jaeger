# Platform tracing contract (shared)

Binding rules for Qubership/NC services migrating to OpenTelemetry. Every skill
layer must enforce these rules or record an explicit `gap`.

## Mandatory contract

### Client libraries

- Preferred client library per language: the official **OpenTelemetry SDK**
  (Java, Go, Python, C++, and any other language OTel supports).
- Wrappers over the OTel SDK are allowed **only** when every other
  rule in this contract still holds.
- A non-OTel SDK is acceptable only when no OTel SDK exists for the language
  — and still must satisfy the rest of this contract.

### Environment parameters

- `TRACING_ENABLED` — tracing on/off for the workload.
- `TRACING_HOST` — OTLP proxy host (default `nc-diagnostic-agent` in the same
  namespace). Alternative in some clusters: `open-telemetry-collector`.
- Sampler env precedence (first match wins):
  `TRACING_SAMPLER_RATELIMITING` → `TRACING_SAMPLER_PROBABILISTIC` →
  `TRACING_SAMPLER_CONST`.

Contracted values and in-service defaults:

| Parameter                       | Type    | Allowed values   | Default in service    |
|---------------------------------|---------|------------------|-----------------------|
| `TRACING_ENABLED`               | boolean | `true` / `false` | `false` (tracing off) |
| `TRACING_HOST`                  | string  | valid host       | `nc-diagnostic-agent` |
| `TRACING_SAMPLER_RATELIMITING`  | integer | `>= 0`           | `10` (10 per second)  |
| `TRACING_SAMPLER_PROBABILISTIC` | float   | `0.01`–`1.0`     | `0.01` (1%)           |
| `TRACING_SAMPLER_CONST`         | integer | `0` or `1`       | `1` (100%)            |

Use `TRACING_SAMPLER_RATELIMITING` when the stack supports a rate-limiting sampler; fall back to
`TRACING_SAMPLER_PROBABILISTIC`, then to `TRACING_SAMPLER_CONST`, in that order.

### Export

- OTLP exporter format: `http/protobuf` only.
- Canonical endpoint: `http://${TRACING_HOST}:4318/v1/traces`.
- Default `TRACING_HOST`: `nc-diagnostic-agent` (OTel proxy in the same namespace).
- Alternative proxy in some clusters: `open-telemetry-collector`.
- The proxy exists so services never hardcode direct Jaeger links (Jaeger is
  usually deployed in another namespace); it exposes tracing-protocol endpoints
  and forwards to Jaeger.
- Production path: service → proxy/collector → Jaeger. **Direct-to-Jaeger** is
  fallback/dev only — not the platform contract for migrated services.
- Do not keep Jaeger client, OpenTracing, or legacy Zipkin exporters as the
  active export path.

### Propagation

- Contract default: `b3multi` when B3 peer compatibility is required.
- B3 propagators are not part of the core SDK in most languages — add the
  language's B3 propagator module when `b3` / `b3multi` is configured
  (Java: `opentelemetry-extension-trace-propagators`; Go:
  `go.opentelemetry.io/contrib/propagators/b3`).

#### Inject and extract are two different sets

Propagation is **not** one list. The two directions behave differently, and
neither is a "pick one" (verified by disassembly — see the table below):

- **Extract is a race.** Several formats are tried; effectively **one** supplies
  the context. Order decides which.
- **Inject is a fan-out.** A composite calls `inject` on **every** configured
  propagator, so **all** its formats are written to the outgoing request. Order
  is irrelevant here; there is no "winner".

Record and reason about the two sets separately in L1, L2, and the schemas — a
single `formats` list hides the failure mode where a service reads B3 fine and
still emits only `traceparent` to B3-only peers.

Consequence for configuration surfaces: **a single list cannot express
"extract several, inject one".**

| Surface | Inject set | Extract set |
|---------|-----------|-------------|
| `OTEL_PROPAGATORS`, `quarkus.otel.propagators`, Go composite | the **whole** list — every format is written | the whole list |
| Spring Boot `produce` / `consume` | only `produce` | only `consume` |

So `OTEL_PROPAGATORS=b3multi,tracecontext` emits **both** `X-B3-*` and
`traceparent` on every outgoing call. That is usually harmless (peers read what
they know) but it is not "inject one" — say so in the plan rather than implying
a choice was made. Only Spring Boot's split lists give real inject/extract
asymmetry without custom code.

#### Changing the wire format is out of scope for a migration

The propagation format is a property of the **fleet**, not of one service. A
one-sided change silently breaks trace continuity with every peer that was
working before.

1. **Format already configured** → **preserve it**. A migration to the OTel SDK
   must carry the same inject format across. Switching formats is never part of
   the migration diff.
2. **Configured format conflicts with the contract default above** → do not
   "fix" it. Raise it with the user as a question (which peers speak which
   format, who else must change), and record the answer in plan `gaps`.
3. **Tracing introduced from scratch** (maturity Level 1, nothing configured) →
   do **not** pick silently. Ask the user to choose: `B3` (single `b3` header),
   `B3_MULTI` (`X-B3-*`), `W3C` (`traceparent`), or a multi-format set. Offer the
   contract default as the suggestion; the choice is the user's.
4. **Multi-format** is a supported answer: accept several formats inbound, and
   emit whatever the surface emits — on a single-list surface that means **all**
   configured formats go out, which is expected, not a bug. Do not build extra
   machinery around it — the working assumption is that adjacent tooling does not
   overwrite an already-present trace context.

#### Ask once per fleet, not once per service

The format is a fleet property, so the question is **scope-level**, asked once,
even when the migration covers many services in several languages. Do not walk
the user through one prompt per service — N identical questions invite N
inconsistent answers, which is the exact failure the rule exists to prevent.

| Situation in scope | Handling |
| --- | --- |
| Several services, **none** has tracing | **One** question for the whole scope. Apply the answer to every target, in each framework's own syntax and order. |
| Several services, **some** already configured | No question about those — preserve each one. Ask only if the greenfield services must interoperate with them, and then offer the existing format as the default answer. |
| Existing services **disagree** with each other | Do not normalize silently. Report the split with file paths and ask which format is the fleet's intended one. |
| A service talks only to peers outside the scope | Flag it separately — its peers, not this migration, decide its format. |

Record the answer once at scope level and reuse it; each service's plan cites
the scope decision rather than re-deriving it. Per-language syntax and list
order still differ — the **decision** is shared, the **encoding** is not.

#### Extract order is priority — and the direction differs per framework

**This section is about extraction only** (inject writes everything — above).
Where several propagators are configured, list order decides which one supplies
the context. The winning end is **not** the same across stacks, and the two
families get there by different mechanics:

| Stack                          | Composite implementation                           | Winner    | Mechanism |
|--------------------------------|----------------------------------------------------|-----------|-----------|
| Go OTel SDK                    | `NewCompositeTextMapPropagator`                    | **last**  | chains the context through **all** propagators; the last one that finds anything overwrites |
| Quarkus / Pure Java (OTel SDK) | `MultiTextMapPropagator`                           | **last**  | same — loops the whole array, reassigning `ctx` |
| Spring Boot, Brave bridge      | `CompositePropagationFactory$CompositePropagation` | **first** | returns at the **first** extractor whose result is not `EMPTY` |
| Spring Boot, OTel bridge       | `CompositeTextMapPropagator`                       | **first** | breaks at the **first** extractor that changes the context |

Verified by disassembly: `spring-boot-actuator-autoconfigure:3.5.11`,
`opentelemetry-context:1.57.0`, `go.opentelemetry.io/otel@v1.43.0`
(`propagation/propagation.go:130-141`).

Boot 4 is confirmed too: the OTel-bridge composite moved to
`org.springframework.boot.micrometer.tracing.opentelemetry.autoconfigure.CompositeTextMapPropagator`
in `spring-boot-micrometer-tracing-opentelemetry:4.0.2`, and its `extract`
bytecode is **identical** to Boot 3.5.11 — still first-wins.

The mechanism difference matters when a **stale or duplicate** header is
present: Boot stops at the first hit and ignores the rest, while the OTel/Go
composites let a later propagator silently overwrite an already-extracted
context.

Consequence: one list `[W3C, B3, B3_MULTI]` yields the **opposite** priority on
Quarkus and on Spring Boot. The common advice "put the preferred format last" is
true only for OTel-native composites, and an end-to-end test will not catch a
wrong order.

**List order is the agent's job, never a question for the user.** Split it:

| Decision | Who |
| --- | --- |
| Which format(s) the service speaks, and which wins when a request carries more than one | **user** (or preserved from existing config) |
| Which end of the list that maps to | **agent** — derive it from the table above |

Asking a developer whether the winner is first or last is asking them to recite
framework internals. Take the user's intent ("we're a B3 fleet, B3 wins"), then
emit `[W3C, B3_MULTI]` on Quarkus and `[B3_MULTI, W3C]` on Spring Boot — two
different lists expressing the same intent. State the resulting order and the
reason in the plan `note` so a reviewer can check it without knowing the table.

Note this only changes behavior for requests arriving with **several** formats
at once. With one format inbound, every order works, which is why a wrong order
survives testing.

#### Framework defaults are asymmetric — record them in L1

An unconfigured framework is not an inert framework. Spring Boot ships
(metadata of both artifacts above):

- `management.tracing.propagation.consume` = `[W3C, B3, B3_MULTI]`
- `management.tracing.propagation.produce` = `[W3C]`

So an unconfigured Boot service accepts B3 on the way in and emits **W3C only**
on the way out — silently incompatible with a B3 fleet on outgoing calls while
incoming calls look healthy. "Not configured" ≠ "nothing works": capture the
effective default, not the absence of a key.

Confirmed in both generations, by constructor bytecode and by
`spring-configuration-metadata.json`: `spring-boot-actuator-autoconfigure:3.5.11`
and `spring-boot-micrometer-tracing:4.0.2` (`produce = List.of(W3C)`,
`consume = List.of(PropagationType.values())`).

**Trap — `management.tracing.propagation.type` overrides both.** It is a *list*
property, not a single value, and `getEffectiveProducedTypes()` /
`getEffectiveConsumedTypes()` both return `type` whenever it is non-null,
ignoring `produce` and `consume` entirely. Setting `type` therefore also
discards the lenient `consume` default. Never emit `type` alongside
`produce`/`consume` — the latter two become dead config that reads as active.

#### Build-time vs runtime — mark it explicitly

Whether the format can be changed without a rebuild decides whether a request
like "make the propagation format switchable" is feasible at all.

| Surface                                             | Scope          |
|-----------------------------------------------------|----------------|
| `quarkus.otel.propagators`                          | **build-time** — rebuild required |
| Spring Boot `propagation.produce` / `.consume`      | runtime        |
| Pure Java `OTEL_PROPAGATORS`                        | runtime        |
| Go `OTEL_PROPAGATORS` / programmatic setup          | runtime        |

#### Verify constructor defaults, never assume them

When the contract names a wire format, the L4 plan must name the concrete
constructor or option that produces it, checked against the SDK source **of the
version the repository actually depends on**. Line numbers below are pinned to
`go.opentelemetry.io/contrib/propagators/b3@v1.42.0` (identical in `@v1.35.0`);
re-read them for another version rather than trusting the citation.

Worked example — Go `b3.New()` with no options injects the **single** `b3`
header, not `X-B3-*`:

- `b3_config.go:43,51,55` — `B3Unspecified = 0`, then `B3MultipleHeader = 1 << iota`
  (**2**) and `B3SingleHeader` (**4**).
- `b3_config.go:37` — `supports(o)` is `e&o == o`. With `e = B3Unspecified = 0`
  this is **false for every** `o`: `0&4 != 4`, `0&2 != 2`.
- `b3_propagator.go:84` — the single-header branch is
  `supports(B3SingleHeader) || InjectEncoding == B3Unspecified`. `supports` is
  false; the **`== B3Unspecified` clause** is what makes the branch fire. The
  default writes `b3` by explicit fallback, not by bitmask.
- `b3_propagator.go:103` — the multi branch is `supports(B3MultipleHeader)`
  alone, with no `B3Unspecified` fallback, so `X-B3-*` is never written by
  default.

Multi-header injection therefore requires
`b3.New(b3.WithInjectEncoding(b3.B3MultipleHeader))`.

The same file proves the inject/extract split above:
`b3_propagator.go:123` declares `func (propagator) Extract(...)` — an
**unnamed receiver**, so extraction cannot read `InjectEncoding` at all. It tries
the single `b3` header first and falls back to the multi headers
(`:129-145`) regardless of how injection is configured. Lenient in, strict out,
in twenty lines.

### Sampling

- OTel sampler: `parentbased_traceidratio` (or equivalent platform wiring).
- Semantics: always continue traces when the incoming request already carries
  sampled trace headers; apply the configured ratio to new root traces.
- Wire the ratio to `TRACING_SAMPLER_PROBABILISTIC` (per the sampler env
  precedence above).
- Never `always_on` as the production default.

### Service naming

- `service.name=${service_name}-${namespace_name}` (resolved at runtime).
- Rationale: unlike Monitoring or Logging, Jaeger carries no namespace/pod
  meta-information, so without the namespace suffix identical services deployed
  in several namespaces are indistinguishable in the trace backend.
- The value must be **resolved** at runtime — a literal unexpanded placeholder
  (e.g. `${NAMESPACE:unknown}` surviving into the exported resource) is a
  contract violation.
- How `service.name` is set is framework-specific — see the language package
  config recipes; the composed `${name}-${namespace}` shape is the same
  everywhere.

#### Namespace sources (inside a Kubernetes pod)

Discover and record the namespace source in discovery evidence. Two supported
ways:

1. **Environment variable injection** — Kubernetes Downward API
   (`fieldRef: metadata.namespace`), a deployer-provided `NAMESPACE` value, or
   Helm built-ins (`.Release.Namespace`).
2. **Mounted service-account file** — read
   `/var/run/secrets/kubernetes.io/serviceaccount/namespace` (mounted
   automatically with the pod's ServiceAccount).

### Endpoint filtering

Exclude probes, metrics, and management endpoints from trace export (health,
actuator, OpenAPI, metrics paths — per framework).

General rules for what to trace:

- endpoint participates in a request chain (receives and/or fans out calls) —
  **must** be traced;
- endpoint runs heavy logic inside the service — **must** be traced;
- endpoint is not part of the public API and is never called by other services
  — should **not** be traced;
- endpoint belongs to a service/debug API (probes, metrics, management) —
  should **not** be traced.

Always-excluded endpoint types: container probes (`/liveness`, `/livez`,
`/readiness`, `/healthz`), metrics endpoints (`/metrics`, `/prometheus`), and
framework management endpoints (`/actuator/*`, `/q/*`).

### Log correlation

- Mandatory `traceId` and `spanId` in application logs (pattern or MDC).
- Expected log shape:
  `[yyyy-MM-ddTHH:mm:ss.SSS] ... [traceId=<value>] [spanId=<value>] ...`
- Existing logging integrations may already satisfy this — confirm in real log
  output before adding another correlation layer.
- Log correlation and span export are independent checks: backend spans do not
  prove IDs in logs, and vice versa.

### Retired libraries

Remove and do not re-introduce as active export paths:

- Jaeger Java client
- OpenTracing API/implementations used as the primary tracer
- Spring Cloud Sleuth, Brave/Zipkin as the sole tracing stack (migrate to OTel)

Language packages may add framework-specific wiring, but **cannot override**
these rules.

## Operational constraints

| Situation                             | Required skill behavior                                                                    |
|---------------------------------------|--------------------------------------------------------------------------------------------|
| Exporter unavailable / collector down | Runtime cannot be `pass`; record buffering/drop risk; set `manual` or `fail` with evidence |
| SDK overhead                          | Do not hard-assert fixed CPU/memory numbers; note overhead is workload-dependent           |
| Third-party SDK regressions           | Recommend verifying SDK version and known issue trackers when symptoms match               |
| Framework/logging wrappers            | Allowed only if log contract above still holds; confirm output before stacking layers      |

Collector/exporter unavailability semantics (SDK defaults): spans buffer
in memory in the batch processor queue (default `maxQueueSize` 2048); when the
queue is full new spans are **dropped**, never persisted to disk; memory and GC
pressure can grow while the endpoint is down. All limits are configurable —
record buffering/drop risk instead of asserting data loss cannot happen.

## Runtime validation

Before declaring runtime `pass`:

- Confirm target collector/proxy alias and endpoint match this contract.
- Traces must reach the platform backend through the documented export path.

## Agent vs user visibility

- Evaluate compliance in `discovery-result.platformContract` (L1 facts) and
  `capability-result.platformContract` (L2 verdicts) — required JSON, internal.
- In user chat briefs, describe gaps in **plain language** with file paths — do
  not expose facet keys or `PASS`/`FAILED` tokens.

## Skill coverage map

| Contract area           | Where enforced                                                   |
|-------------------------|------------------------------------------------------------------|
| Detection / L1 evidence | Language `reference/detection-rules.md`, `models/1-discovery.md` |
| L2 verdicts             | Umbrella `models/2-capability.md`                                |
| L3 maturity             | Umbrella `models/3-maturity.md`                                  |
| L4 migration            | Umbrella `models/4-transformation.md` + language `recipes/`      |
| L5 validation           | Umbrella `models/5-validation.md` + language runtime recipes     |
| Build/registry blockers | Language `reference/build-preconditions.md`                      |
