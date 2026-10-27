#!/usr/bin/env bash
#
# Verifies the Jaeger v2 Elasticsearch/OpenSearch index rotation configuration
# rendered into the query runtime config. The format depends on the Jaeger
# version of the query image:
# * before 2.20.0: legacy use_aliases/use_ilm and index level date_layout/rollover_frequency;
# * 2.20.0 and later: indices.<type>.rotation and no deprecated rotation flags.

set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_dir="$(cd "${chart_dir}/../.." && pwd)"
work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

legacy_image="jaegertracing/jaeger:2.13.0"
rotation_image="jaegertracing/jaeger:2.20.0"
digest="sha256:0000000000000000000000000000000000000000000000000000000000000000"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

helm_template() {
    helm template jaeger "${chart_dir}" \
        --namespace jaeger \
        --set jaeger.storage.type=elasticsearch \
        --set elasticsearch.client.url=elasticsearch.example.svc:9200 \
        --set elasticsearch.client.username=admin \
        --set elasticsearch.client.password=admin \
        "$@"
}

# render <name> [helm args...] renders the query runtime config into ${work_dir}/<name>.yaml.
render() {
    local name="$1"
    shift
    local secret="${work_dir}/${name}.secret"
    helm_template --show-only templates/query/secret.yaml "$@" \
        2>"${work_dir}/${name}.err" | tr -d '\r' >"${secret}" || return 1
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

assert_count() {
    local name="$1" pattern="$2" expected="$3" actual
    actual="$(grep -Ec -- "${pattern}" "${work_dir}/${name}.yaml" || true)"
    [[ "${actual}" -eq "${expected}" ]] ||
        fail "${name}: expected ${expected} matches for '${pattern}', found ${actual}"
}

# assert_next_line <name> <line pattern> <next line pattern>: every line matching the first
# pattern is followed by a line matching the second one, blank lines are ignored.
assert_next_line() {
    local name="$1" pattern="$2" next="$3"
    # awk does not support \s.
    awk -v p="${pattern//\\s/[[:space:]]}" -v n="${next//\\s/[[:space:]]}" '
        /^[[:space:]]*$/ { next }
        prev { if ($0 !~ n) bad = 1; prev = 0 }
        $0 ~ p { prev = 1; found = 1 }
        END { exit !(found && !bad) }
    ' "${work_dir}/${name}.yaml" || fail "${name}: '${pattern}' is not followed by '${next}'"
}

deprecated='^\s+(use_aliases|use_ilm|span_read_alias|span_write_alias|service_read_alias|service_write_alias):'

assert_no_deprecated() {
    assert_count "$1" "${deprecated}" 0
}

assert_no_rotation() {
    assert_count "$1" '^\s+(rotation|periodic|manual_rollover|auto_rollover):' 0
}

# Jaeger before 2.20.0 (the default image): legacy format, no indices.<type>.rotation.

render legacy_default
assert_count legacy_default '^\s+use_aliases: false$' 1
assert_count legacy_default '^\s+use_ilm:' 0
assert_no_rotation legacy_default

render legacy_aliases --set elasticsearch.useAliases=true
assert_count legacy_aliases '^\s+use_aliases: true$' 1
assert_no_rotation legacy_aliases

render legacy_ilm \
    --set elasticsearch.useAliases=true \
    --set elasticsearch.useIlm=true \
    --set elasticsearch.createMappings=false
assert_count legacy_ilm '^\s+use_aliases: true$' 1
assert_count legacy_ilm '^\s+use_ilm: true$' 1
assert_count legacy_ilm '^\s+create_mappings: false$' 1
assert_no_rotation legacy_ilm

render legacy_periodic \
    --set elasticsearch.indices.spans.dateLayout=2006-01-02-15 \
    --set elasticsearch.indices.spans.rolloverFrequency=hour
assert_next_line legacy_periodic '^\s+spans:$' '^\s+date_layout: "2006-01-02-15"$'
assert_next_line legacy_periodic '^\s+date_layout: ' '^\s+rollover_frequency: "hour"$'
assert_no_rotation legacy_periodic

# The same settings on an explicitly selected older image.
render legacy_explicit_image --set query.image=jaegertracing/jaeger:2.19.0 --set elasticsearch.useAliases=true
assert_count legacy_explicit_image '^\s+use_aliases: true$' 1
assert_no_rotation legacy_explicit_image

render legacy_example -f "${repo_dir}/docs/examples/opensearch/opensearch-one-node-values.yaml"
assert_count legacy_example '^\s+use_aliases: true$' 1
assert_count legacy_example '^\s+shards: 1$' 4
assert_no_rotation legacy_example

# Jaeger 2.20.0 and later: indices.<type>.rotation, no deprecated rotation flags.

render rotation_default --set query.image="${rotation_image}"
assert_no_deprecated rotation_default
assert_no_rotation rotation_default

render rotation_aliases --set query.image="${rotation_image}" --set elasticsearch.useAliases=true
assert_no_deprecated rotation_aliases
assert_count rotation_aliases '^\s+manual_rollover: \{\}$' 4
assert_count rotation_aliases '^\s+(auto_rollover|periodic):' 0

render rotation_ilm \
    --set query.image="${rotation_image}" \
    --set elasticsearch.useAliases=true \
    --set elasticsearch.useIlm=true \
    --set elasticsearch.createMappings=false
assert_no_deprecated rotation_ilm
assert_count rotation_ilm '^\s+auto_rollover: \{\}$' 4
assert_count rotation_ilm '^\s+manual_rollover:' 0
assert_count rotation_ilm '^\s+create_mappings: false$' 1

render rotation_periodic \
    --set query.image="${rotation_image}" \
    --set elasticsearch.indices.spans.dateLayout=2006-01-02-15 \
    --set elasticsearch.indices.spans.rolloverFrequency=hour
assert_no_deprecated rotation_periodic
assert_count rotation_periodic '^\s+periodic:$' 1
assert_next_line rotation_periodic '^\s+periodic:$' '^\s+date_layout: "2006-01-02-15"$'
assert_next_line rotation_periodic '^\s+date_layout: ' '^\s+rollover_frequency: "hour"$'
assert_count rotation_periodic '^\s+(date_layout|rollover_frequency):' 2

render rotation_example --set query.image="${rotation_image}" \
    -f "${repo_dir}/docs/examples/opensearch/opensearch-one-node-values.yaml"
assert_no_deprecated rotation_example
assert_count rotation_example '^\s+manual_rollover: \{\}$' 4
assert_count rotation_example '^\s+shards: 1$' 4

# Explicit per-index rotation takes precedence over useAliases, other types keep manual_rollover.
cat >"${work_dir}/explicit-values.yaml" <<'EOF'
elasticsearch:
  useAliases: true
  indexPrefix: prod
  indices:
    spans:
      shards: 3
      rotation:
        periodic:
          date_layout: "2006-01-02"
    services:
      rotation:
        auto_rollover:
          read_alias: custom-read
          write_alias: custom-write
          policy_name: jaeger-ilm-policy
EOF
render rotation_explicit --set query.image="${rotation_image}" -f "${work_dir}/explicit-values.yaml"
assert_no_deprecated rotation_explicit
assert_count rotation_explicit '^\s+periodic:$' 1
assert_count rotation_explicit '^\s+auto_rollover:$' 1
assert_count rotation_explicit '^\s+policy_name: jaeger-ilm-policy$' 1
assert_count rotation_explicit '^\s+read_alias: custom-read$' 1
assert_count rotation_explicit '^\s+write_alias: custom-write$' 1
assert_count rotation_explicit '^\s+manual_rollover: \{\}$' 2
assert_count rotation_explicit '^\s+shards: 3$' 1
assert_count rotation_explicit '^\s+index_prefix: "prod"$' 1

# Older versions do not support explicit rotation.
expect_render_error legacy_explicit \
    "elasticsearch.indices.spans.rotation requires Jaeger 2.20.0 or later, but the query image is Jaeger 2.13.0" \
    -f "${work_dir}/explicit-values.yaml"

# Invalid combinations are rejected at render time for both formats.
for image in "${legacy_image}" "${rotation_image}"; do
    expect_render_error ilm_without_aliases \
        "elasticsearch.useIlm=true requires elasticsearch.useAliases=true" \
        --set query.image="${image}" --set elasticsearch.useIlm=true --set elasticsearch.createMappings=false
    expect_render_error ilm_with_create_mappings \
        "elasticsearch.useIlm=true requires elasticsearch.createMappings=false" \
        --set query.image="${image}" --set elasticsearch.useAliases=true --set elasticsearch.useIlm=true
done

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
    --set query.image="${rotation_image}" -f "${work_dir}/rotation-and-date-values.yaml"

# Image references: the version is the tag of the last path segment, a "v" prefix and a
# digest suffix are allowed, query.jaegerVersion takes precedence over the tag.

render image_registry_port \
    --set query.image="registry.example.com:5000/jaegertracing/jaeger:v2.20.0@${digest}" \
    --set elasticsearch.useAliases=true
assert_no_deprecated image_registry_port
assert_count image_registry_port '^\s+manual_rollover: \{\}$' 4

render image_suffix --set query.image=jaegertracing/jaeger:2.19.1-custom --set elasticsearch.useAliases=true
assert_count image_suffix '^\s+use_aliases: true$' 1
assert_no_rotation image_suffix

render image_version_override \
    --set query.image="${rotation_image}" \
    --set query.jaegerVersion=2.13.0 \
    --set elasticsearch.useAliases=true
assert_count image_version_override '^\s+use_aliases: true$' 1
assert_no_rotation image_version_override

# Unknown version (digest only, custom tag): without rotation settings neither format is rendered,
# with rotation settings query.jaegerVersion is required.
render image_digest_default --set query.image="jaegertracing/jaeger@${digest}"
assert_no_deprecated image_digest_default
assert_no_rotation image_digest_default

for image in "jaegertracing/jaeger@${digest}" "jaegertracing/jaeger:latest" "registry.example.com:5000/jaeger"; do
    expect_render_error image_unknown_aliases "Set query.jaegerVersion" \
        --set query.image="${image}" --set elasticsearch.useAliases=true
done
expect_render_error image_unknown_periodic "Set query.jaegerVersion" \
    --set query.image=jaegertracing/jaeger:custom --set elasticsearch.indices.spans.rolloverFrequency=hour

render image_digest_version \
    --set query.image="jaegertracing/jaeger@${digest}" \
    --set query.jaegerVersion=v2.20.0 \
    --set elasticsearch.useAliases=true
assert_no_deprecated image_digest_version
assert_count image_digest_version '^\s+manual_rollover: \{\}$' 4

expect_render_error image_invalid_version "is not a semantic version" \
    --set query.jaegerVersion=2.20 --set elasticsearch.useAliases=true

# No deprecated rotation flags anywhere in the full chart rendered for Jaeger 2.20.0.
helm_template \
    --set query.image="${rotation_image}" \
    --set collector.image="${rotation_image}" \
    --set elasticsearch.useAliases=true \
    --set elasticsearch.useIlm=true \
    --set elasticsearch.createMappings=false \
    --set elasticsearch.rollover.install=true | tr -d '\r' >"${work_dir}/full.yaml"
assert_no_deprecated full

echo "Elasticsearch rotation configuration tests passed."
