# troubleshoot-jaeger

A single user-invoked skill that diagnoses problems with Qubership Jaeger (a Helm chart that deploys a Jaeger v2
distributed-tracing stack on Kubernetes and OpenShift).

The skill is **read-only and advisory**. It does not run `kubectl`, SSH, or Ansible, and it never changes a system. It
reads a pasted problem description plus any attached logs or configuration, matches the symptom against a curated
reference, and returns a diagnosis with remediation steps and a list of data to collect when the match is uncertain.

## Contents

| Path | Purpose |
| ---- | ------- |
| [`SKILL.md`](.apm/skills/troubleshoot-jaeger/SKILL.md) | The diagnosis procedure. |
| [`references/troubleshooting.md`](.apm/skills/troubleshoot-jaeger/references/troubleshooting.md) | Symptom-indexed failure catalog. |
| [`scripts/show_cases.py`](.apm/skills/troubleshoot-jaeger/scripts/show_cases.py) | Symptom-catalog and section reader. |

The reference is also exposed at `docs/troubleshooting.md` in the repository root via a symlink.
