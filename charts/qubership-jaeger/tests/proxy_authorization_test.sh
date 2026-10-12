#!/usr/bin/env bash

set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
rendered_file="${work_dir}/rendered.yaml"
error_file="${work_dir}/error.txt"
trap 'rm -rf "${work_dir}"' EXIT

config_template="templates/query/auth-proxy/proxy-secret-config.yaml"
token_template="templates/query/auth-proxy/proxy-secret-oauth-token.yaml"
deployment_template="templates/query/deployment.yaml"

oauth2_args=(
    --set proxy.install=true
    --set proxy.type=oauth2
    --set proxy.oauth2.tokenEndpoint=https://idp.example.com/realms/test/protocol/openid-connect/token
    --set proxy.oauth2.authorizationEndpoint=https://idp.example.com/realms/test/protocol/openid-connect/auth
    --set proxy.oauth2.clientId=jaeger
    --set proxy.oauth2.clientToken=secret
    --set proxy.oauth2.idpAddress=idp.example.com
    --set proxy.oauth2.idpPort=443
)
authorization_args=(
    --set proxy.oauth2.authorization.enabled=true
    --set proxy.oauth2.authorization.jwksUri=https://idp.example.com/realms/test/protocol/openid-connect/certs
)

render() {
    local template="$1"
    shift

    helm template jaeger "${chart_dir}" --namespace jaeger --show-only "${template}" "$@"
}

assert_count() {
    local pattern="$1"
    local expected="$2"
    local file="${3:-${rendered_file}}"
    local actual

    actual="$(grep -Ec -- "${pattern}" "${file}" || true)"
    if [[ "${actual}" -ne "${expected}" ]]; then
        echo "Expected ${expected} matches for '${pattern}', found ${actual}." >&2
        exit 1
    fi
}

assert_render_fails() {
    local expected_message="$1"
    shift

    if render "${config_template}" "$@" >/dev/null 2>"${error_file}"; then
        echo "Expected rendering to fail with '${expected_message}', but it succeeded." >&2
        exit 1
    fi
    if ! grep -Fq -- "${expected_message}" "${error_file}"; then
        echo "Expected rendering to fail with '${expected_message}', got:" >&2
        cat "${error_file}" >&2
        exit 1
    fi
}

# Prints one key of a rendered Secret, without the indentation of the block scalar.
extract_secret_key() {
    local key="$1"
    local file="$2"

    awk -v key="${key}" '
        $0 ~ "^  " key ": [|>]-$" { found = 1; next }
        found && /^  [^ ]/ { exit }
        found { sub(/^    /, ""); print }
    ' "${file}"
}

# Authorization is disabled by default.
render "${config_template}" "${oauth2_args[@]}" >"${rendered_file}"
assert_count 'envoy\.filters\.http\.oauth2$' 1
assert_count 'envoy\.filters\.http\.jwt_authn' 0
assert_count 'envoy\.filters\.http\.rbac' 0
assert_count 'local_reply_config' 0

# Basic authentication ignores the authorization parameters.
render "${config_template}" \
    --set proxy.install=true \
    --set proxy.type=basic \
    "${authorization_args[@]}" \
    --set 'proxy.oauth2.authorization.allowedRoles={jaeger-user}' >"${rendered_file}"
assert_count 'envoy\.filters\.http\.jwt_authn' 0
assert_count 'envoy\.filters\.http\.rbac' 0

# Each allowed role renders a list matcher and a string matcher.
render "${config_template}" "${oauth2_args[@]}" "${authorization_args[@]}" \
    --set 'proxy.oauth2.authorization.allowedRoles={jaeger-user,jaeger-admin}' >"${rendered_file}"
assert_count '- name: envoy\.filters\.http\.jwt_authn$' 1
assert_count '- name: envoy\.filters\.http\.rbac$' 1
assert_count 'local_reply_config' 1
assert_count '- sourced_metadata:' 4
assert_count 'list_match:' 2
assert_count 'path: \[\{"key":"jwt_payload"\},\{"key":"realm_access"\},\{"key":"roles"\}\]' 4
assert_count 'exact: "jaeger-user"' 2
assert_count 'exact: "jaeger-admin"' 2
assert_count 'uri: "https://idp\.example\.com/realms/test/protocol/openid-connect/certs"' 1
assert_count 'issuer:' 0
assert_count 'audiences:' 0

# Each allowed user renders one matcher.
render "${config_template}" "${oauth2_args[@]}" "${authorization_args[@]}" \
    --set 'proxy.oauth2.authorization.allowedUsers={alice,bob}' >"${rendered_file}"
assert_count '- sourced_metadata:' 2
assert_count 'list_match:' 0
assert_count 'path: \[\{"key":"jwt_payload"\},\{"key":"preferred_username"\}\]' 2
assert_count 'exact: "alice"' 1
assert_count 'exact: "bob"' 1

# Roles and users combine in one policy. A claim name can be a URI, and values can contain YAML syntax.
cat >"${work_dir}/values.yaml" <<'EOF'
proxy:
  oauth2:
    authorization:
      issuer: https://idp.example.com/adfs
      audiences:
        - jaeger
      rolesClaim:
        - http://schemas.microsoft.com/ws/2008/06/identity/claims/role
      allowedRoles:
        - 'CN=Jaeger Users,OU=Groups: "Tracing"'
      userClaim: upn
      allowedUsers:
        - alice@example.com
EOF
render "${config_template}" "${oauth2_args[@]}" "${authorization_args[@]}" \
    --values "${work_dir}/values.yaml" >"${rendered_file}"
assert_count '- sourced_metadata:' 3
assert_count 'issuer: "https://idp\.example\.com/adfs"' 1
assert_count 'audiences: \["jaeger"\]' 1
assert_count '\{"key":"http://schemas\.microsoft\.com/ws/2008/06/identity/claims/role"\}' 2
assert_count 'exact: "CN=Jaeger Users,OU=Groups: \\"Tracing\\""' 2
assert_count 'path: \[\{"key":"jwt_payload"\},\{"key":"upn"\}\]' 1
assert_count 'exact: "alice@example\.com"' 1

# The rendered configuration must load in the Envoy version that the chart ships.
if [[ "${SKIP_ENVOY_VALIDATION:-false}" == "true" ]]; then
    echo "SKIP_ENVOY_VALIDATION is true, skipping the Envoy configuration check."
else
    envoy_dir="${work_dir}/envoy"
    mkdir -p "${envoy_dir}/oauth2"
    render "${token_template}" "${oauth2_args[@]}" >"${work_dir}/token.yaml"
    render "${deployment_template}" "${oauth2_args[@]}" >"${work_dir}/deployment.yaml"
    extract_secret_key "config.yaml" "${rendered_file}" >"${envoy_dir}/config.yaml"
    extract_secret_key "token-secret.yaml" "${work_dir}/token.yaml" >"${envoy_dir}/oauth2/token-secret.yaml"
    extract_secret_key "hmac-secret.yaml" "${work_dir}/token.yaml" >"${envoy_dir}/oauth2/hmac-secret.yaml"
    chmod -R a+rX "${work_dir}"

    envoy_image="$(awk '/^ +- name: proxy$/ { found = 1; next } found && /^ +image:/ { print $2; exit }' \
        "${work_dir}/deployment.yaml")"
    if [[ -z "${envoy_image}" ]]; then
        echo "Cannot find the proxy container image in the rendered query deployment." >&2
        exit 1
    fi

    if ! docker run --rm --volume "${envoy_dir}:/envoy:ro" "${envoy_image}" \
        --mode validate --config-path /envoy/config.yaml \
        --service-cluster envoy --service-node envoy >"${work_dir}/envoy.log" 2>&1; then
        echo "Envoy ${envoy_image} rejected the rendered configuration:" >&2
        cat "${work_dir}/envoy.log" >&2
        exit 1
    fi
    # A deprecated field still loads, but a later Envoy release removes it.
    assert_count 'Deprecated field' 0 "${work_dir}/envoy.log"
fi

# A changed allowlist must change the pod template, otherwise Envoy keeps the old configuration.
render "${deployment_template}" "${oauth2_args[@]}" "${authorization_args[@]}" \
    --set 'proxy.oauth2.authorization.allowedUsers={alice}' >"${work_dir}/deployment-alice.yaml"
render "${deployment_template}" "${oauth2_args[@]}" "${authorization_args[@]}" \
    --set 'proxy.oauth2.authorization.allowedUsers={bob}' >"${work_dir}/deployment-bob.yaml"
render "${deployment_template}" >"${work_dir}/deployment-no-proxy.yaml"
assert_count '^ +checksum/proxy-config: [0-9a-f]{64}$' 1 "${work_dir}/deployment-alice.yaml"
assert_count '^ +checksum/proxy-config: [0-9a-f]{64}$' 1 "${work_dir}/deployment-bob.yaml"
assert_count 'checksum/proxy-config' 0 "${work_dir}/deployment-no-proxy.yaml"
if [[ "$(grep 'checksum/proxy-config' "${work_dir}/deployment-alice.yaml")" == \
    "$(grep 'checksum/proxy-config' "${work_dir}/deployment-bob.yaml")" ]]; then
    echo "Expected checksum/proxy-config to change when allowedUsers changes." >&2
    exit 1
fi

# The checksum must stay stable between renders, otherwise every upgrade restarts the pod.
render "${deployment_template}" "${oauth2_args[@]}" "${authorization_args[@]}" \
    --set 'proxy.oauth2.authorization.allowedUsers={alice}' >"${work_dir}/deployment-alice-again.yaml"
if [[ "$(grep 'checksum/proxy-config' "${work_dir}/deployment-alice.yaml")" != \
    "$(grep 'checksum/proxy-config' "${work_dir}/deployment-alice-again.yaml")" ]]; then
    echo "Expected checksum/proxy-config to stay the same for identical values." >&2
    exit 1
fi

assert_render_fails \
    "proxy.oauth2.authorization.enabled is true, but jwksUri is empty" \
    "${oauth2_args[@]}" \
    --set proxy.oauth2.authorization.enabled=true \
    --set 'proxy.oauth2.authorization.allowedUsers={alice}'
assert_render_fails \
    "allowedRoles and allowedUsers are both empty" \
    "${oauth2_args[@]}" "${authorization_args[@]}"
assert_render_fails \
    "proxy.oauth2.authorization.allowedRoles is set, but rolesClaim is empty" \
    "${oauth2_args[@]}" "${authorization_args[@]}" \
    --set 'proxy.oauth2.authorization.allowedRoles={jaeger-user}' \
    --set-json 'proxy.oauth2.authorization.rolesClaim=[]'
assert_render_fails \
    "proxy.oauth2.authorization.allowedUsers is set, but userClaim is empty" \
    "${oauth2_args[@]}" "${authorization_args[@]}" \
    --set 'proxy.oauth2.authorization.allowedUsers={alice}' \
    --set proxy.oauth2.authorization.userClaim=

echo "Proxy authorization test passed."
