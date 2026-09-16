#!/usr/bin/env bash

set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
rendered_file="$(mktemp)"
openshift_file="$(mktemp)"
openshift_override_file="$(mktemp)"
custom_context_file="$(mktemp)"
error_file="$(mktemp)"
trap 'rm -f "${rendered_file}" "${openshift_file}" "${openshift_override_file}" "${custom_context_file}" "${error_file}"' EXIT

helm template jaeger "${chart_dir}" \
    --namespace jaeger \
    --set hotrod.install=true \
    --set integrationTests.install=true \
    --set proxy.install=true \
    --set elasticsearch.client.tls.enabled=true \
    --set elasticsearch.indexCleaner.install=true \
    --set elasticsearch.lookback.install=true \
    --set elasticsearch.rollover.install=true \
    --set spark.install=true \
    --set jaeger.storage.type=elasticsearch >"${rendered_file}"

assert_count() {
    local pattern="$1"
    local expected="$2"
    local file="${3:-${rendered_file}}"
    local actual

    actual="$(grep -Ec "${pattern}" "${file}" || true)"
    if [[ "${actual}" -ne "${expected}" ]]; then
        echo "Expected ${expected} matches for '${pattern}', found ${actual}." >&2
        exit 1
    fi
}

assert_regular_containers_hardened() {
    local file="$1"

    awk '
        function indentation(line, value) {
            value = line
            sub(/[^ ].*$/, "", value)
            return length(value)
        }

        function start_container(line) {
            container_name = line
            sub(/^[ ]*- name:[ ]*/, "", container_name)
            allow_privilege_escalation = 0
            read_only_root = 0
            drop_all = 0
            tmp_mount = 0
            in_container = 1
            container_count++
        }

        function finish_container(missing) {
            if (!in_container) {
                return
            }

            missing = ""
            if (!allow_privilege_escalation) {
                missing = missing " allowPrivilegeEscalation=false"
            }
            if (!read_only_root) {
                missing = missing " readOnlyRootFilesystem=true"
            }
            if (!drop_all) {
                missing = missing " capabilities.drop=ALL"
            }
            if (!tmp_mount) {
                missing = missing " mountPath=/tmp"
            }
            if (missing != "") {
                printf "Container %s in %s is missing:%s\n", container_name, source, missing > "/dev/stderr"
                failed = 1
            }
            in_container = 0
        }

        /^# Source:/ {
            source = $0
            sub(/^# Source:[ ]*/, "", source)
        }

        {
            line = $0
            if (line ~ /^[ ]*containers:[ ]*$/) {
                finish_container()
                in_containers = 1
                containers_indent = indentation(line)
                item_indent = -1
                next
            }

            if (!in_containers || line ~ /^[ ]*$/) {
                next
            }

            indent = indentation(line)
            if (item_indent < 0) {
                if (line ~ /^[ ]*- name:[ ]*/) {
                    item_indent = indent
                    start_container(line)
                } else if (indent <= containers_indent) {
                    in_containers = 0
                }
                next
            }

            if (indent == item_indent && line ~ /^[ ]*- name:[ ]*/) {
                finish_container()
                start_container(line)
                next
            }

            if (indent <= item_indent) {
                finish_container()
                in_containers = 0
                next
            }

            if (line ~ /^[ ]*allowPrivilegeEscalation:[ ]*false[ ]*$/) {
                allow_privilege_escalation = 1
            } else if (line ~ /^[ ]*readOnlyRootFilesystem:[ ]*true[ ]*$/) {
                read_only_root = 1
            } else if (line ~ /^[ ]*- ALL[ ]*$/) {
                drop_all = 1
            } else if (line ~ /^[ ]*mountPath:[ ]*\/tmp[ ]*$/) {
                tmp_mount = 1
            }
        }

        END {
            finish_container()
            if (container_count == 0) {
                print "No regular containers found in rendered manifests." > "/dev/stderr"
                failed = 1
            }
            exit failed
        }
    ' "${file}"
}

assert_render_fails() {
    local expected_message="$1"
    shift

    if helm template jaeger "${chart_dir}" "$@" >/dev/null 2>"${error_file}"; then
        echo "Expected Helm rendering to reject an incompatible security context." >&2
        exit 1
    fi
    if ! grep -Fq "${expected_message}" "${error_file}"; then
        echo "Helm rendering failed without the expected message: ${expected_message}" >&2
        cat "${error_file}" >&2
        exit 1
    fi
}

assert_count '^kind: (Deployment|Job|CronJob)$' 10
assert_count '^[[:space:]]+runAsNonRoot: true$' 10
assert_count '^[[:space:]]+type: RuntimeDefault$' 10
assert_count '^[[:space:]]+runAsUser: 1000$' 10
assert_count '^[[:space:]]+runAsGroup: 1000$' 10
assert_count '^[[:space:]]+fsGroup: 1000$' 10
assert_count '^[[:space:]]+allowPrivilegeEscalation: false$' 13
assert_count '^[[:space:]]+readOnlyRootFilesystem: true$' 13
assert_count '^[[:space:]]+- ALL$' 13
assert_count '^[[:space:]]+mountPath: /tmp$' 13
assert_count '^[[:space:]]+sizeLimit: 100Mi$' 10
assert_count '^[[:space:]]+- name: PYTHONDONTWRITEBYTECODE$' 2
assert_regular_containers_hardened "${rendered_file}"

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
    --api-versions security.openshift.io/v1 >"${openshift_file}"

if grep -Eq '^[[:space:]]+(runAs(User|Group)|fsGroup):' "${openshift_file}"; then
    echo "Automatically detected OpenShift manifests must not pin a user or group ID." >&2
    exit 1
fi

helm template jaeger "${chart_dir}" \
    --namespace jaeger \
    --set PAAS_PLATFORM=OPENSHIFT >"${openshift_override_file}"

if grep -Eq '^[[:space:]]+(runAs(User|Group)|fsGroup):' "${openshift_override_file}"; then
    echo "The OpenShift platform override must not pin a user or group ID." >&2
    exit 1
fi

helm template jaeger "${chart_dir}" \
    --namespace jaeger \
    --set collector.securityContext.runAsUser=2000 \
    --set collector.securityContext.runAsGroup=2000 \
    --set collector.securityContext.fsGroup=2000 >"${custom_context_file}"

assert_count '^[[:space:]]+runAsUser: 2000$' 1 "${custom_context_file}"
assert_count '^[[:space:]]+runAsGroup: 2000$' 1 "${custom_context_file}"
assert_count '^[[:space:]]+fsGroup: 2000$' 1 "${custom_context_file}"

assert_render_fails \
    "securityContext.runAsNonRoot must be true when security hardening is enabled" \
    --set collector.securityContext.runAsNonRoot=false
assert_render_fails \
    "value must be 'RuntimeDefault'" \
    --set collector.securityContext.seccompProfile.type=Unconfined
assert_render_fails \
    "containerSecurityContext.allowPrivilegeEscalation must be false when security hardening is enabled" \
    --set collector.containerSecurityContext.allowPrivilegeEscalation=true
assert_render_fails \
    "containerSecurityContext.readOnlyRootFilesystem must be true when security hardening is enabled" \
    --set collector.containerSecurityContext.readOnlyRootFilesystem=false
assert_render_fails \
    "containerSecurityContext.seccompProfile.type must be RuntimeDefault when security hardening is enabled" \
    --set collector.containerSecurityContext.seccompProfile.type=Unconfined
assert_render_fails \
    "containerSecurityContext.capabilities.drop must contain ALL when security hardening is enabled" \
    --set 'collector.containerSecurityContext.capabilities.drop[0]=NET_RAW'

echo "Security hardening smoke test passed."
