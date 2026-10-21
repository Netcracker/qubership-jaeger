#!/usr/bin/env bash
#
# Verifies the Jaeger v2 Elasticsearch/OpenSearch index rotation configuration
# rendered into the query runtime config: no deprecated rotation flags and a
# valid `indices.<type>.rotation` structure.
#
# If JAEGER_BIN points to a Jaeger v2.20+ binary, every valid rendered config is
# additionally checked with `jaeger validate`.

set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_dir="$(cd "${chart_dir}/../.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# render <name> [helm args...] renders the query runtime config into ${work_dir}/<name>.yaml.
render() {
    local name="$1"
    shift
    local secret="${work_dir}/${name}.secret"
    helm template jaeger "${chart_dir}" \
        --namespace jaeger \
        --set jaeger.storage.type=elasticsearch \
        --set elasticsearch.client.url=elasticsearch.example.svc:9200 \
        --set elasticsearch.client.scheme=https \
        --set elasticsearch.client.username=admin \
        --set elasticsearch.client.password=admin \
        --show-only templates/query/secret.yaml \
        "$@" 2>"${work_dir}/${name}.err" | tr -d '\r' >"${secret}" || return 1
    # Extract the config.yaml payload of the Secret.
    awk '
        /^stringData:/ { s = 1; next }
        s && /^  config.yaml: \|/ { c = 1; next }
        c { if ($0 ~ /^[^ ]/) exit; sub(/^    /, ""); print }
    ' "${secret}" >"${work_dir}/${name}.yaml"
    [[ -s "${work_dir}/${name}.yaml" ]] || fail "${name}: empty rendered config"
}

# expect_render_error <name> <message fragment> [helm args...]
expect_render_error() {
    local name="$1" fragment="$2"
    shift 2
    if render "${name}" "$@" 2>/dev/null; then
        fail "${name}: rendering was expected to fail"
    fi
    grep -qF -- "${fragment}" "${work_dir}/${name}.err" ||
        fail "${name}: error does not contain '${fragment}': $(cat "${work_dir}/${name}.err")"
}

count() {
    local pattern="$1" name="$2" actual
    actual="$(grep -Ec -- "${pattern}" "${work_dir}/${name}.yaml" || true)"
    echo "${actual}"
}

assert_count() {
    local name="$1" pattern="$2" expected="$3" actual
    actual="$(count "${pattern}" "${name}")"
    [[ "${actual}" -eq "${expected}" ]] ||
        fail "${name}: expected ${expected} matches for '${pattern}', found ${actual}"
}

assert_no_deprecated() {
    assert_count "$1" '^\s+(use_aliases|use_ilm|span_read_alias|span_write_alias|service_read_alias|service_write_alias):' 0
}

jaeger_validate() {
    local name="$1"
    [[ -n "${JAEGER_BIN:-}" ]] || return 0
    local out config="${work_dir}/${name}.yaml"
    # A native Windows binary (Git Bash) needs a Windows style path.
    if command -v cygpath >/dev/null 2>&1; then
        config="$(cygpath -m "${config}")"
    fi
    if ! out="$("${JAEGER_BIN}" validate --config="file:${config}" 2>&1)"; then
        fail "${name}: jaeger validate failed: ${out}"
    fi
    if grep -q '^Error' <<<"${out}"; then
        fail "${name}: jaeger validate failed: ${out}"
    fi
}

# Defaults: daily indices, nothing rotation related is rendered.
render default
assert_no_deprecated default
assert_count default '^\s+rotation:' 0
jaeger_validate default

# useAliases: manual_rollover for all four index types.
render aliases --set elasticsearch.useAliases=true
assert_no_deprecated aliases
assert_count aliases '^\s+manual_rollover: \{\}$' 4
assert_count aliases '^\s+(auto_rollover|periodic):' 0
jaeger_validate aliases

# Index prefix, shards and replicas are preserved next to the rotation.
render aliases_settings \
    --set elasticsearch.useAliases=true \
    --set elasticsearch.indexPrefix=prod \
    --set elasticsearch.indices.spans.shards=2 \
    --set elasticsearch.indices.spans.replicas=0
assert_no_deprecated aliases_settings
assert_count aliases_settings '^\s+index_prefix: "prod"$' 1
assert_count aliases_settings '^\s+shards: 2$' 1
assert_count aliases_settings '^\s+replicas: 0$' 1
assert_count aliases_settings '^\s+manual_rollover: \{\}$' 4
jaeger_validate aliases_settings

# useIlm: auto_rollover for all four index types.
render ilm \
    --set elasticsearch.useAliases=true \
    --set elasticsearch.useIlm=true \
    --set elasticsearch.createMappings=false
assert_no_deprecated ilm
assert_count ilm '^\s+auto_rollover: \{\}$' 4
assert_count ilm '^\s+manual_rollover:' 0
assert_count ilm '^\s+create_mappings: false$' 1
jaeger_validate ilm

# dateLayout/rolloverFrequency are moved under rotation.periodic.
render periodic \
    --set elasticsearch.indices.spans.dateLayout=2006-01-02-15 \
    --set elasticsearch.indices.spans.rolloverFrequency=hour
assert_no_deprecated periodic
assert_count periodic '^\s+periodic:$' 1
assert_count periodic '^\s{18}date_layout: "2006-01-02-15"$' 1
assert_count periodic '^\s{18}rollover_frequency: "hour"$' 1
assert_count periodic '^\s+(date_layout|rollover_frequency):' 2
jaeger_validate periodic

# Explicit rotation takes precedence over useAliases, other types keep manual_rollover.
cat >"${work_dir}/mixed-values.yaml" <<'EOF'
elasticsearch:
  useAliases: true
  indices:
    spans:
      shards: 3
      rotation:
        periodic:
          date_layout: "2006-01-02"
    services:
      rotation:
        auto_rollover:
          policy_name: jaeger-ilm-policy
EOF
render mixed -f "${work_dir}/mixed-values.yaml"
assert_no_deprecated mixed
assert_count mixed '^\s+periodic:$' 1
assert_count mixed '^\s+auto_rollover:$' 1
assert_count mixed '^\s+policy_name: jaeger-ilm-policy$' 1
assert_count mixed '^\s+manual_rollover: \{\}$' 2
assert_count mixed '^\s+shards: 3$' 1
jaeger_validate mixed

# Explicit auto_rollover does not depend on the legacy useAliases/useIlm inputs.
cat >"${work_dir}/explicit-auto-values.yaml" <<'EOF'
elasticsearch:
  createMappings: false
  indices:
    spans:
      rotation:
        auto_rollover:
          read_alias: custom-read
          write_alias: custom-write
EOF
render explicit_auto -f "${work_dir}/explicit-auto-values.yaml"
assert_no_deprecated explicit_auto
assert_count explicit_auto '^\s+auto_rollover:$' 1
assert_count explicit_auto '^\s+read_alias: custom-read$' 1
assert_count explicit_auto '^\s+write_alias: custom-write$' 1
jaeger_validate explicit_auto

# Invalid combinations are rejected at render time.
expect_render_error ilm_without_aliases \
    "elasticsearch.useIlm=true requires elasticsearch.useAliases=true" \
    --set elasticsearch.useIlm=true --set elasticsearch.createMappings=false
expect_render_error ilm_with_create_mappings \
    "elasticsearch.useIlm=true requires elasticsearch.createMappings=false" \
    --set elasticsearch.useAliases=true --set elasticsearch.useIlm=true

cat >"${work_dir}/rotation-and-date-values.yaml" <<'EOF'
elasticsearch:
  indices:
    spans:
      dateLayout: "2006-01-02"
      rotation:
        manual_rollover: {}
EOF
expect_render_error rotation_and_date \
    "cannot be combined with dateLayout or rolloverFrequency" \
    -f "${work_dir}/rotation-and-date-values.yaml"

# Existing OpenSearch examples render valid configuration.
for example in opensearch-simple-values opensearch-rollover-values opensearch-one-node-values; do
    render "${example}" -f "${repo_dir}/docs/examples/opensearch/${example}.yaml"
    assert_no_deprecated "${example}"
    jaeger_validate "${example}"
done
assert_count opensearch-simple-values '^\s+rotation:' 0
assert_count opensearch-rollover-values '^\s+rotation:' 0
assert_count opensearch-one-node-values '^\s+manual_rollover: \{\}$' 4
assert_count opensearch-one-node-values '^\s+shards: 1$' 4
assert_count opensearch-one-node-values '^\s+replicas: 0$' 4

echo "Elasticsearch rotation configuration tests passed."
