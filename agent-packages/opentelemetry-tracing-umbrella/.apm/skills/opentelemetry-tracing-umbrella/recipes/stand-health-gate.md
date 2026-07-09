# Recipe — stand health gate (L5 runtime, step 1)

**Run this immediately after deploy completes and before log-error triage, Jaeger
queries, or any runtime `pass` verdict.**

Spans in Jaeger or a one-off cURL **do not** satisfy this gate. Probe traffic on
an unstable workload can still export traces while the runtime keeps restarting
the process.

## When to run

- Runtime end-to-end is in progress (dev-minimal or user cluster).
- SUT manifest is applied; rollout is in progress or finished.

Skip only when `validationPlan.runtime.status` is `manual` (no deploy).

## Mandatory order (L5 runtime)

```text
deploy → stand health gate (this recipe) → log-error triage → business traffic → tracing assertions → pass/fail → validation cleanup (on pass)
```

**Forbidden:** querying Jaeger, posting "end-to-end success", or setting
`runtime.status` to `pass` before this gate passes.

## Gate checklist (environment-agnostic)

Use the runtime's documented tools (Kubernetes CLI, compose health checks,
process supervisor, load-balancer target state, etc.). Replace placeholders
with the active namespace, workload name, and service endpoint.

### 1. Wait for rollout / startup complete

The deploy reports finished — rollout succeeded, containers started, or the
equivalent health transition for the chosen runtime.

**Stop** on timeout or failed deploy. Inspect events and logs; do not proceed to
tracing checks.

### 2. Workload Ready and stable

**Pass only when all hold:**

| Check             | Pass                                           | Fail (stop — fix stand first)                                |
|-------------------|------------------------------------------------|--------------------------------------------------------------|
| Process phase     | Running / healthy                              | Crash loop, error exit, stuck pending beyond expected window |
| Ready signal      | Expected ready count (e.g. `1/1`)              | Not ready, perpetual terminating/creating                    |
| Restarts          | `0`, or stable and explained after triage      | Restart storm, count increasing during observation           |
| Network endpoints | Non-empty target for the client-facing service | Empty targets while claiming availability                    |
| Rollout / deploy  | Completed successfully                         | Failed / timed out                                           |

If **any** row fails, set `runtime.status` to `fail` (record evidence in plan
root `gaps`). **Do not** query Jaeger as a substitute for a healthy workload.

### 3. Observation window (catch liveness-kill loops)

After step 2 first shows ready, wait **at least 60 seconds**, then re-check
ready/restart state.

**Stop** if ready dropped, restarts increased, or phase is no longer healthy.
This catches workloads that pass startup/readiness briefly then fail liveness
(for example `/probes/live` returning 503).

### 4. Probe and event sanity (when restarts > 0 or ready flaps)

Inspect workload events and recent logs (current and previous instance if
restarted).

Look for liveness/startup probe failures, back-off restarting, recurring
`ERROR`/`FATAL`. Record evidence in plan root `gaps`.

### 5. SUT responds through the client network path

HTTP `2xx` on a **non-suppressed** business path from
[`../models/5-validation.md`](../models/5-validation.md) §5.3 — through the service
name or load balancer clients use, not only in-container localhost when a front
service exists.

## Kubernetes example

When the environment is Kubernetes, typical commands:

```bash
kubectl rollout status deployment/<deploy> -n <ns> --timeout=300s
kubectl get pods -n <ns> -l app=<sut-label> -o wide
kubectl get endpoints <svc> -n <ns>
# after 60s observation:
kubectl get pods -n <ns> -l app=<sut-label>
# when restarts > 0 or ready flaps:
kubectl describe pod -n <ns> -l app=<sut-label> | tail -40
kubectl logs -n <ns> deploy/<deploy> --tail=100
kubectl logs -n <ns> deploy/<deploy> --previous --tail=50
# business path through Service:
kubectl run curl-sut -n <ns> --rm -i --restart=Never --image=curlimages/curl -- \
  curl -sf -o /dev/null -w '%{http_code}' http://<svc>:<port>/<business-path>
```

Map checklist rows: rollout → step 1; pod Ready/restarts/endpoints → step 2;
observation re-check → step 3; describe/logs → step 4; Service cURL → step 5.

## Outcomes

| Outcome              | Next step                                                                      |
|----------------------|--------------------------------------------------------------------------------|
| All checks pass      | Run [`log-error-triage.md`](log-error-triage.md), then tracing assertions      |
| Any check fails      | Fix manifest/config/secrets/probes; redeploy; **re-run this gate from step 1** |
| Fixed during session | Re-run steps 1–3 after rollout restart before claiming pass                    |

## User-facing brief (mandatory before tracing checks)

Post after step 3 (even when about to fail):

```markdown
### L5 Stand health — <service-name> @ <environment>
- **Rollout:** succeeded | failed | timeout
- **Ready:** `<x>/<y>`, RESTARTS `<n>`, phase `<phase>`
- **Endpoints:** `<target>` | empty
- **Observation window:** stable | restarts increased | ready lost
- **Verdict:** pass | fail — <one-line reason>
- **Next:** log-error triage + tracing | fix stand (do not query Jaeger yet)
```

## JSON artifact

Embed under `validationPlan.runtime.standHealth`:

```json
{
  "passed": true,
  "podReady": "1/1",
  "restarts": 0,
  "endpointsNonEmpty": true,
  "observationWindowStable": true,
  "evidence": "rollout status OK; RESTARTS 0 after 60s; endpoints 10.42.0.24:8080"
}
```

Set `passed=false` when any gate row fails. Runtime `pass` is forbidden while
`standHealth.passed` is false or absent.
