# Layer 2 — Trace capability (shared)

**Goal:** judge what tracing capabilities *actually work*, using only
`discovery-result.json` as input. Do not re-scan the repository.

- **Input:** `discovery-result.json` from Layer 1.
- **Output:** `capability-result.json` → [`../schemas/L2-capability-result.schema.json`](../schemas/L2-capability-result.schema.json).

Verdict scale:

| Verdict   | Use when                                                                           |
|-----------|------------------------------------------------------------------------------------|
| `PASS`    | Discovery evidence shows the capability is present and correctly wired.            |
| `PARTIAL` | Capability is present but incomplete, unverified, or mixed (legacy + OTel).        |
| `FAILED`  | Evidence shows broken wiring, contract violation, or context loss with no wrapper. |
| `UNKNOWN` | A required discovery field is missing — record the reason in `gaps`.               |

## Algorithm

1. **Propagation** — read `configuration.propagation` and `asyncBoundaries`:
   - `http`: from `propagation.components.http` when present; else infer from
     HTTP-capable stack (framework + export config).
   - `kafka`: required when any `kafka-producer` / `kafka-consumer` boundary
     exists; `FAILED` when boundary exists and `contextWrapper` is false or
     component signal is `FAILED`.
   - `async`: required when executor/reactor/completable-future boundaries exist;
     same wrapper rule as Kafka.
   - `injectFormat`: judge `propagation.inject` (the format written outbound) —
     `PASS` when it matches the format the peers expect, `FAILED` when it does
     not, `UNKNOWN` when discovery could not resolve it. Note that an empty
     `inject` set does **not** mean "nothing is emitted": use the framework
     default recorded in L1 (Spring Boot defaults to `[W3C]` on produce).
   - `extractFormats`: judge `propagation.extract` (formats accepted inbound).
     Lenient extraction is normal — several formats here are not a defect.
   - `overall`: worst applicable component verdict (`FAILED` > `PARTIAL` >
     `UNKNOWN` > `PASS`). When no tracing stack exists, set `overall` to
     `UNKNOWN`.

   Never collapse inject and extract into one verdict. A service that extracts
   B3 correctly and injects W3C looks healthy inbound and breaks every peer
   outbound — see
   [`../reference/platform-tracing-guide.md`](../reference/platform-tracing-guide.md)
   §Propagation.

2. **Span quality** — read `apiUsage`, `instrumentation`, and `dependencyProfile`:
   - `lifecycle`: `PASS` when span create/end is evidenced or instrumentation
     mode is `auto`; `FAILED` when manual spans lack close/end; `UNKNOWN` when
     mode is `none`.
   - `hierarchy`: `PASS` when parent-child is evidenced or auto-instrumentation
     covers the exercised paths; `FAILED` when async boundaries lack context
     wrappers; `UNKNOWN` when there are no boundaries to judge.
   - `attributes` / `errors`: from API usage (`setAttribute`, `recordException`,
     legacy tags); `UNKNOWN` when mode is `none` and no API usage exists.
   - Map discovery `OK` / `FAILED` component flags to capability verdicts; do
     not upgrade `FAILED` to `PASS` without counter-evidence.

3. **Export** — read `dependencyProfile` and `configuration.export`:
   - `exporterExists`: `PASS` when `hasExporter` is true or OTel SDK/agent is
     wired; `FAILED` when tracing deps exist but no exporter path.
   - `endpointSet`: `PASS` when endpoint/host is configured; `FAILED` when export
     is expected but endpoint is null or legacy-only without OTLP path.
   - `protocolValid`: `PASS` for OTLP `http/protobuf` toward platform shape;
     `PARTIAL` for OTLP with wrong protocol or legacy Zipkin/Jaeger client path.
   - `pipelineWired`: `PASS` when exporter, endpoint, and protocol align;
     `FAILED` when export cannot reach the platform collector/proxy.
   - `overall`: worst sub-verdict.

4. **Platform contract** — **always** emit `capability-result.platformContract`
   with all six facets below. Map from `discovery-result.platformContract` when
   present; otherwise infer from `configuration`, `dependencyProfile`, and
   `instrumentation`, or set `UNKNOWN` and record why in `gaps`. Facets follow
   [`../reference/platform-tracing-guide.md`](../reference/platform-tracing-guide.md)
   (mandatory platform rules):

   | JSON facet             | Platform rule                                                                                                                                      |
   |------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
   | `serviceNameNamespace` | `service.name` = `<service>-<namespace>`                                                                                                           |
   | `sampler`              | `parentbased_traceidratio`; never `always_on`; sampler env precedence                                                                              |
   | `propagationStandard`  | Inject set matches the format peers expect (contract default `b3multi`) + required propagator extension; extract set covers the peers that call in |
   | `endpointFilter`       | Probes / metrics / management excluded from trace export                                                                                           |
   | `loggingCorrelation`   | `traceId` and `spanId` in logs                                                                                                                     |
   | `exportShape`          | OTLP `http/protobuf` to platform endpoint via `TRACING_HOST`                                                                                       |

   Treat mandatory contract gaps as `FAILED`, not `UNKNOWN`, unless discovery
   could not inspect the source file. Use `notes[]` for file citations — internal
   to JSON only.

5. **Gaps** — carry forward unresolved Layer 1 `gaps` and add any facet marked
   `UNKNOWN` because evidence was insufficient.

Validate the result against
[`../schemas/L2-capability-result.schema.json`](../schemas/L2-capability-result.schema.json).

## User-facing vs JSON (platform contract)

- **Always** include `platformContract` in `capability-result.json` (all six
  facets) — it is **required** by schema. Maturity and L4/L5 read it; omitting
  the block is invalid even though users never see it in chat.
- **Never** expose to the user: the `platformContract` object, facet keys
  (`serviceNameNamespace`, `exportShape`, …), or verdict tokens (`PASS`,
  `PARTIAL`, `FAILED`, `UNKNOWN`).
- In the **L2 Capability brief**, translate contract outcomes into plain language
  (what works, what violates the platform tracing guide, with file paths). Same
  style as L3 — no schema enums in chat. Template: language root skill (Java:
  `opentelemetry-tracing-java` `SKILL.md` §3.1).
