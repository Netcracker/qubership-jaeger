#!/usr/bin/env bash

set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered_file="$(mktemp)"
openshift_file="$(mktemp)"
trap 'rm -f "${rendered_file}" "${openshift_file}"' EXIT

helm template jaeger "${chart_dir}" \
    --namespace jaeger \
    --set PAAS_PLATFORM=KUBERNETES \
    --set hotrod.install=true \
    --set integrationTests.install=true \
    --set proxy.install=true \
    --set elasticsearch.indexCleaner.install=true \
    --set elasticsearch.lookback.install=true \
    --set elasticsearch.rollover.install=true \
    --set spark.install=true \
    --set jaeger.storage.type=elasticsearch >"${rendered_file}"

assert_count() {
    local pattern="$1"
    local expected="$2"
    local actual

    actual="$(grep -Ec "${pattern}" "${rendered_file}" || true)"
    if [[ "${actual}" -ne "${expected}" ]]; then
        echo "Expected ${expected} matches for '${pattern}', found ${actual}." >&2
        exit 1
    fi
}

assert_count '^kind: (Deployment|Job|CronJob)$' 10
assert_count '^[[:space:]]+runAsNonRoot: true$' 10
assert_count '^[[:space:]]+type: RuntimeDefault$' 10
assert_count '^[[:space:]]+runAsUser: 1000$' 10
assert_count '^[[:space:]]+runAsGroup: 1000$' 10
assert_count '^[[:space:]]+allowPrivilegeEscalation: false$' 13
assert_count '^[[:space:]]+readOnlyRootFilesystem: true$' 13
assert_count '^[[:space:]]+- ALL$' 13
assert_count '^[[:space:]]+mountPath: /tmp$' 13
assert_count '^[[:space:]]+sizeLimit: 100Mi$' 10

if grep -Eq 'hostNetwork: true|hostPID: true|hostIPC: true|hostPath:' "${rendered_file}"; then
    echo "Rendered workloads use a forbidden host namespace or hostPath volume." >&2
    exit 1
fi

while read -r port; do
    if (((port >= 17 && port <= 995) || \
        port == 1080 || port == 1236 || port == 1433 || port == 1434 || \
        port == 1494 || port == 1512 || port == 1524 || port == 1525 || \
        port == 1645 || port == 1646 || port == 1649 || port == 1758 || \
        port == 1759 || port == 1789 || port == 1812 || port == 1911 || \
        port == 26000)); then
        echo "Rendered workloads use forbidden container port ${port}." >&2
        exit 1
    fi
done < <(sed -n 's/^[[:space:]]*- containerPort: \([0-9][0-9]*\)$/\1/p' "${rendered_file}")

helm template jaeger "${chart_dir}" \
    --namespace jaeger \
    --set PAAS_PLATFORM=OPENSHIFT >"${openshift_file}"

if grep -Eq '^[[:space:]]+runAs(User|Group):' "${openshift_file}"; then
    echo "OpenShift manifests must not pin a user or group ID." >&2
    exit 1
fi

echo "Security hardening smoke test passed."
