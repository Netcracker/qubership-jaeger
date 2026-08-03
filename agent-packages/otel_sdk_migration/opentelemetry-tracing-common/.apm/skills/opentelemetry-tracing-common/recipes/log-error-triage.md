# Recipe — runtime log error triage (L5, step 2)

After [`stand-health-gate.md`](stand-health-gate.md) passes and **before**
Jaeger queries or setting `validationPlan.runtime.status` to `pass`, scan workload logs
and classify every distinct `ERROR`/`FATAL` (or OTel export failure) line. Do not
ignore log noise — **explicitly** state whether errors are stale, benign, or blocking.

Skip only when the runtime tier is `manual` (no cluster deploy). This step is not
a substitute for stand health: `Running` with `0/1 Ready` or `CrashLoopBackOff`
means step 1 failed — fix the stand first, do not triage around it.

## Collection checklist

Run against the active runtime deployment and collect:

1. Current workload identity and start timestamp.
2. Current-process logs since start time (`ERROR`/`FATAL`/export failures).
3. Previous-process logs only when restarts occurred.
4. Tracing backend/proxy logs for the same window.

Prefer logs **since current process start**. Lines that appear only in previous
instance logs are candidates for **stale**.

## Classification (mandatory per finding)

Assign exactly one bucket to each distinct error signature (message + logger class, not every duplicate line):

| Bucket             | Meaning                                                                                                                                                           | end-to-end impact                             |
|--------------------|-------------------------------------------------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------|
| `stale`            | From a **previous** pod/container or pre-fix boot; absent in logs since current pod became Ready                                                                  | Does **not** block end-to-end pass            |
| `benign`           | Recurring but **unrelated** to tracing/L4 scope (known dev-only misconfig, optional feature, third-party noise) **and** SUT is Ready + business endpoint succeeds | Does **not** block end-to-end pass — cite why |
| `blocks-e2e`       | Active in current pod logs **and** indicates SUT or export path is broken (encryption, DB, readiness, OTel export, crash loop)                                    | **Blocks** `runtime.status` `pass`            |
| `tracing-adjacent` | OTel/Jaeger/export/propagator related; may or may not block depending on span export                                                                              | Block if spans missing or export fails        |
| `unknown`          | Cannot classify — insufficient evidence                                                                                                                           | Treat as **blocking** until resolved          |

### Heuristics

**Likely `stale` when:**

- Workload restart count is non-zero and the error appears only in previous logs.
- Error timestamp is **before** pod `startTime` (from an earlier rollout you fixed).
- Error was from startup race (e.g. DB not ready) and **no recurrence** after Ready.

**Likely `benign` when (all must hold):**

- Error is a documented dev-stack gap (invalid placeholder secret fixed before Ready).
- Business endpoint returns the expected status **after** Ready.
- Error is not in the OTel export, encryption, or DB connectivity path.

**Likely `tracing-adjacent` when:**

- SUT logs report deprecated or mismatched tracing configuration keys for the framework
  in use (export disabled until L4 config is applied); Jaeger may show only sidecar/probe services.
- `Failed to export spans` or OTLP connection errors in SUT logs.

**Likely `blocks-e2e` when:**

- Same error repeats **after** Ready (e.g. encryption misconfig,
  `Failed to export spans`, Flyway/DB connection failures).
- Restarts increased after Ready.
- Readiness/liveness probes return 503 due to the error.
- Service endpoints empty while the pod is `Running`.

**Tracing migration scope:** errors in encryption, DB, or security config are
**not** caused by OTel by default — classify as `blocks-e2e` for stand health,
but note **"outside L4 tracing diff"** in the summary so reviewers know the
migration artifact may still be valid.

## User-facing brief (mandatory)

After triage, post a short block in chat **before** declaring runtime pass/fail:

```markdown
### L5 Log errors — <service-name> @ <environment>
- **Verdict:** none | stale-only | benign (N) | blocks-e2e (N) | mixed
- **Active findings:** … (or "none in current pod since Ready")
- **Stale / fixed:** … (e.g. encryption secret before key regen)
- **End-to-end impact:** does / does not block tracing validation
- **Evidence:** workload startTime, log query snippet, trace query result
```

Do **not** say "errors in logs but end-to-end passed" without this brief.

## JSON artifact

Embed under `validationPlan.runtime.logErrorTriage`:

```json
{
  "verdict": "none | stale-only | benign | blocks-e2e | mixed | unknown",
  "e2eBlocked": false,
  "podStartTime": "<workload start timestamp>",
  "summary": "<one line: what was found and why it does or does not block>",
  "findings": [
    { "signature": "<message + logger>", "classification": "<bucket>",
      "e2eImpact": "<none | blocks>", "evidence": "<where it appears, and where it does not>" }
  ]
}
```

Set `e2eBlocked=true` when any finding has `classification` in
`blocks-e2e`, `tracing-adjacent` (with failed export), or `unknown`.
