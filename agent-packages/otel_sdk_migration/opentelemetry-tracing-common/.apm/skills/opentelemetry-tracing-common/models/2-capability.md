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

1. **Propagation** — read `configuration.propagation` and `asyncBoundaries`. One
   bullet per `capability-result.propagation` field:
   - `http`: from `propagation.components.http` when present; else infer from the
     HTTP-capable stack (framework + export config).
   - `kafka`: required when any `kafka-producer` / `kafka-consumer` boundary exists; `FAILED` when 
     the boundary exists and `contextWrapper` is false or the component signal is `FAILED`.
   - `async`: required when executor/reactor/future boundaries exist; same wrapper rule as Kafka.
   - `injectFormat`: `PASS` when `propagation.inject` matches the format peers expect, 
     `FAILED` when it does not, `UNKNOWN` when discovery could not resolve it.
     An empty `inject` set is not silence — judge the framework default recorded in L1.
   - `extractFormats`: judge `propagation.extract` against the peers that call in.
     Extract and inject are separate sets and separate verdicts —
     [`../reference/platform-tracing-guide.md`](../reference/platform-tracing-guide.md)
     §Propagation.
   - `overall`: worst applicable component verdict (`FAILED` > `PARTIAL` >
     `UNKNOWN` > `PASS`); `UNKNOWN` when no tracing stack exists.

2. **Span quality** — read `apiUsage`, `instrumentation`, and `dependencyProfile`:
   - `lifecycle`: `PASS` when span create/end is evidenced or instrumentation mode is
     `auto`; `FAILED` when manual spans lack close/end; `UNKNOWN` when mode is `none`.
   - `hierarchy`: `PASS` when parent-child is evidenced or auto-instrumentation
     covers the exercised paths; `FAILED` when async boundaries lack context
     wrappers; `UNKNOWN` when there are no boundaries to judge.
   - `attributes` / `errors`: from API usage (`setAttribute`, `recordException`,
     legacy tags); `UNKNOWN` when mode is `none` and no API usage exists.

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
   with all six facets below; L3, L4, and L5 read it, so the block is mandatory
   even though users never see it in chat. Map from
   `discovery-result.platformContract` when present; otherwise infer from
   `configuration`, `dependencyProfile`, and `instrumentation`, or set `UNKNOWN`
   and record why in `gaps`. Facets follow
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

Check the result carries every field listed in
[`../schemas/L2-capability-result.schema.json`](../schemas/L2-capability-result.schema.json) — nothing validates it, so
a skipped facet surfaces only as a gap in the L2 brief.
