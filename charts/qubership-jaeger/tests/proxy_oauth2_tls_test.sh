#!/usr/bin/env bash

set -euo pipefail

chart_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d)"
rendered_file="${work_dir}/rendered.yaml"
error_file="${work_dir}/error.txt"
trap 'rm -rf "${work_dir}"' EXIT

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

# The certificate only has to be a PEM block: neither Helm nor "envoy --mode validate" inspects its content
# beyond parsing it, so a throwaway self-signed certificate is enough.
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=Test CA" \
    -keyout "${work_dir}/ca.key" -out "${work_dir}/ca.pem" 2>/dev/null
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj "/CN=Another test CA" \
    -keyout "${work_dir}/other-ca.key" -out "${work_dir}/other-ca.pem" 2>/dev/null

render() {
    helm template jaeger "${chart_dir}" --namespace jaeger "$@"
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

    if render "$@" >/dev/null 2>"${error_file}"; then
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
    local secret="$1"
    local key="$2"
    local file="$3"

    awk -v secret="${secret}" -v key="${key}" '
        /^---$/ { in_secret = 0; found = 0 }
        $0 == "  name: " secret { in_secret = 1 }
        in_secret && $0 ~ "^  " key ": [|>]-?$" { found = 1; next }
        found && /^  [^ ]/ { found = 0 }
        found { sub(/^    /, ""); print }
    ' "${file}"
}

# Without a CA certificate, the chart renders the TLS settings as before.
render "${oauth2_args[@]}" >"${rendered_file}"
assert_count 'sni: idp\.example\.com$' 1
assert_count 'validation_context:' 0
assert_count 'name: oauth2-idp-ca$' 0
assert_count 'checksum/proxy-oauth2-ca' 0

# An inline CA certificate creates a Secret, mounts it, and turns the verification on.
render "${oauth2_args[@]}" --set-file "proxy.oauth2.tls.ca=${work_dir}/ca.pem" >"${rendered_file}"
assert_count 'validation_context:' 1
assert_count 'filename: /envoy/idp-ca/ca-cert\.pem$' 1
assert_count '- san_type: DNS$' 1
assert_count 'exact: "idp\.example\.com"$' 1
assert_count '^  name: oauth2-idp-ca$' 1
assert_count 'secretName: oauth2-idp-ca$' 1
assert_count 'mountPath: /envoy/idp-ca$' 1
assert_count '^ +checksum/proxy-oauth2-ca: [0-9a-f]{64}$' 1
extract_secret_key "oauth2-idp-ca" "ca-cert.pem" "${rendered_file}" >"${work_dir}/rendered-ca.pem"
if ! diff -qB "${work_dir}/ca.pem" "${work_dir}/rendered-ca.pem" >/dev/null; then
    echo "The rendered oauth2-idp-ca Secret does not contain the configured CA certificate." >&2
    exit 1
fi

# The rendered configuration must load in the Envoy version that the chart ships.
if [[ "${SKIP_ENVOY_VALIDATION:-false}" == "true" ]]; then
    echo "SKIP_ENVOY_VALIDATION is true, skipping the Envoy configuration check."
else
    envoy_dir="${work_dir}/envoy"
    mkdir -p "${envoy_dir}/oauth2" "${envoy_dir}/idp-ca"
    extract_secret_key "proxy-config" "config.yaml" "${rendered_file}" >"${envoy_dir}/config.yaml"
    extract_secret_key "oauth2-token" "token-secret.yaml" "${rendered_file}" >"${envoy_dir}/oauth2/token-secret.yaml"
    extract_secret_key "oauth2-token" "hmac-secret.yaml" "${rendered_file}" >"${envoy_dir}/oauth2/hmac-secret.yaml"
    cp "${work_dir}/rendered-ca.pem" "${envoy_dir}/idp-ca/ca-cert.pem"
    chmod -R a+rX "${work_dir}"

    envoy_image="$(awk '/^ +- name: proxy$/ { found = 1; next } found && /^ +image:/ { print $2; exit }' \
        "${rendered_file}")"
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
    assert_count 'Deprecated field' 0 "${work_dir}/envoy.log"
fi

# A new CA certificate must change the pod template, otherwise Envoy keeps the old one.
first_checksum="$(grep 'checksum/proxy-oauth2-ca' "${rendered_file}")"
render "${oauth2_args[@]}" --set-file "proxy.oauth2.tls.ca=${work_dir}/other-ca.pem" >"${rendered_file}"
if [[ "${first_checksum}" == "$(grep 'checksum/proxy-oauth2-ca' "${rendered_file}")" ]]; then
    echo "Expected checksum/proxy-oauth2-ca to change when the CA certificate changes." >&2
    exit 1
fi

# An existing Secret is mounted as is. The chart creates no Secret and has no content to checksum.
render "${oauth2_args[@]}" \
    --set proxy.oauth2.tls.existingSecret=corporate-ca \
    --set-file "proxy.oauth2.tls.ca=${work_dir}/ca.pem" >"${rendered_file}"
assert_count 'validation_context:' 1
assert_count 'secretName: corporate-ca$' 1
assert_count '^  name: oauth2-idp-ca$' 0
assert_count 'checksum/proxy-oauth2-ca' 0

# An IP address is matched against the IP entries of the certificate.
render "${oauth2_args[@]}" \
    --set proxy.oauth2.idpAddress=10.0.0.15 \
    --set proxy.oauth2.tls.existingSecret=corporate-ca >"${rendered_file}"
assert_count '- san_type: IP_ADDRESS$' 1
assert_count 'exact: "10\.0\.0\.15"$' 1

# The CA settings do not leak into basic authentication or into a disabled proxy.
render --set proxy.install=true --set proxy.type=basic \
    --set proxy.oauth2.tls.existingSecret=corporate-ca >"${rendered_file}"
assert_count 'validation_context:' 0
assert_count 'oauth2-idp-ca' 0
render --set proxy.oauth2.tls.existingSecret=corporate-ca >"${rendered_file}"
assert_count 'oauth2-idp-ca' 0

assert_render_fails \
    "proxy.oauth2.tls sets a CA certificate, but proxy.oauth2.authorizationEndpoint does not start with https://" \
    "${oauth2_args[@]}" \
    --set proxy.oauth2.authorizationEndpoint=http://idp.example.com/auth \
    --set proxy.oauth2.tls.existingSecret=corporate-ca

echo "Proxy OAuth2 TLS test passed."
