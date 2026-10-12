# OAuth2 authorization for Jaeger UI

Implementation plan for [issue 392](https://github.com/Netcracker/qubership-jaeger/issues/392).

## Goal

Restrict Jaeger UI to authorized users when `proxy.type` is `oauth2`. A user gets access if either condition holds:

- The access token carries one of the allowed roles or groups.
- The user is named in an allowlist in the chart values.

The check covers the whole UI, not individual pages. It is off by default, so existing installations keep their
behavior after an upgrade.

## Approach

Add two native Envoy HTTP filters after the existing `oauth2` filter. No new container or image is needed.

| Order | Filter      | Status   | Responsibility                                                              |
| ----- | ----------- | -------- | --------------------------------------------------------------------------- |
| 1     | `lua`       | existing | Returns 401 for `/api/*` requests without the `OauthHMAC` cookie            |
| 2     | `oauth2`    | existing | Runs the login flow and forwards the access token as `Authorization`        |
| 3     | `jwt_authn` | new      | Verifies the token signature against the IdP JWKS and exposes the claims    |
| 4     | `rbac`      | new      | Allows the request if a role claim or the user claim matches, else 403      |
| 5     | `router`    | existing | Proxies to Jaeger Query on port 16686                                       |

The `rbac` filter uses one `ALLOW` policy. Envoy ORs the principals of a policy, which gives the "role or allowlist"
semantics without extra logic.

## Design decisions

- **The roles claim path is a list of keys, not a dotted string.** ADFS claim names are URIs that contain dots, for
  example `http://schemas.microsoft.com/ws/2008/06/identity/claims/role`. Keycloak needs a nested path such as
  `realm_access` → `roles`. A list handles both.
- **Each allowed role renders two matchers.** ADFS emits a string when the user has one group and an array when the
  user has several. One principal uses `list_match.one_of`, the other uses `string_match`.
- **JWKS is fetched through the existing `auth` cluster.** Keycloak and ADFS serve JWKS from the same host as the
  token endpoint, so `idpAddress`, `idpPort`, and the TLS settings are reused. A JWKS endpoint on another host is out
  of scope.
- **The chart fails closed at render time.** `helm template` fails if authorization is enabled without a JWKS URI, or
  with both allowlists empty. An empty policy would lock everyone out.
- **The access token is the only token source.** It must be a JWT. Reading the ID token from the `IdToken` cookie is
  out of scope until someone needs it.
- **Matching is exact and case-sensitive.** No prefix, regex, or case folding.

## Values

New block under `proxy.oauth2`:

```yaml
proxy:
  oauth2:
    authorization:
      # -- Enable the authorization check after a successful OAuth2 login.
      enabled: false
      # -- URL of the IdP JWKS endpoint. Must be served by `idpAddress`. Required when `enabled` is true.
      # Example: `https://my-keycloak.com/auth/realms/test/protocol/openid-connect/certs`
      jwksUri: ""
      # -- Expected `iss` claim. Leave empty to skip the issuer check.
      issuer: ""
      # -- Accepted `aud` values. Leave empty to skip the audience check.
      audiences: []
      # -- Path to the claim that holds roles or groups, one key per list item.
      rolesClaim:
        - realm_access
        - roles
      # -- Roles or groups that grant access.
      allowedRoles: []
      # -- Top-level claim that identifies the user.
      userClaim: preferred_username
      # -- Users that get access regardless of their roles.
      allowedUsers: []
```

## Tasks

### 1. Values and schema

- [x] Add the `proxy.oauth2.authorization` block to `charts/qubership-jaeger/values.yaml` with helm-docs comments.
- [x] Add the matching properties to `charts/qubership-jaeger/values.schema.json`.
- [x] Run `make docs` to regenerate `charts/qubership-jaeger/README.md`.

### 2. Render-time validation

- [x] Add a `proxy.oauth2.authorization.validate` helper to `templates/_helpers.tpl` that calls `fail` when:
  - `jwksUri` is empty;
  - both `allowedRoles` and `allowedUsers` are empty;
  - `allowedRoles` is set and `rolesClaim` is empty;
  - `allowedUsers` is set and `userClaim` is empty.
- [x] Word each message as reason plus action, for example:
  `proxy.oauth2.authorization.enabled is true, but jwksUri is empty. Set jwksUri to the IdP JWKS endpoint.`
- [x] Call the helper from `templates/query/auth-proxy/proxy-secret-config.yaml` inside the `oauth2` branch.

### 3. Envoy configuration

All changes go to the `oauth2` branch of `templates/query/auth-proxy/proxy-secret-config.yaml`, guarded by
`.Values.proxy.oauth2.authorization.enabled`.

- [x] Add the `envoy.filters.http.jwt_authn` filter between `oauth2` and `router`:
  - one provider with `remote_jwks.http_uri` pointing at `jwksUri` through the `auth` cluster, timeout `5s`;
  - optional `issuer` and `audiences`;
  - `payload_in_metadata: jwt_payload` and `forward: true`;
  - one rule that requires the provider for prefix `/`.
- [x] Add the `envoy.filters.http.rbac` filter after `jwt_authn` with action `ALLOW` and a single policy:
  - `permissions: [{any: true}]`;
  - two `sourced_metadata` principals per entry in `allowedRoles`, on the path `jwt_payload` + `rolesClaim`;
  - one `sourced_metadata` principal per entry in `allowedUsers`, on the path `jwt_payload` + `userClaim`.
- [x] Render every user-supplied string with `toJson` so that quotes or colons in a role name cannot break the YAML.
- [x] Add `local_reply_config` to the HTTP connection manager. For status 403, keep the original reason in the body
  and add a hint that points to `/signout`.

Sketch of the policy for `allowedRoles: [jaeger-user]` and `allowedUsers: [alice]`:

```yaml
principals:
  - sourced_metadata:
      metadata_matcher:
        filter: envoy.filters.http.jwt_authn
        path: [{key: jwt_payload}, {key: realm_access}, {key: roles}]
        value:
          list_match:
            one_of:
              string_match: {exact: "jaeger-user"}
  - sourced_metadata:
      metadata_matcher:
        filter: envoy.filters.http.jwt_authn
        path: [{key: jwt_payload}, {key: realm_access}, {key: roles}]
        value:
          string_match: {exact: "jaeger-user"}
  - sourced_metadata:
      metadata_matcher:
        filter: envoy.filters.http.jwt_authn
        path: [{key: jwt_payload}, {key: preferred_username}]
        value:
          string_match: {exact: "alice"}
```

### 4. Restart the pod on configuration change

Envoy reads `config.yaml` once at startup, and the query deployment has no checksum annotation. Without this task, an
edited allowlist takes effect only after a manual restart.

- [x] Add a `checksum/proxy-config` pod annotation to `templates/query/deployment.yaml`, computed from the rendered
  `proxy-secret-config.yaml`. Render it only when `proxy.install` is true.
- [x] Leave `proxy-secret-oauth-token.yaml` out of the checksum. Its HMAC secret is regenerated on every render and
  would restart the pod on every upgrade.

### 5. Tests

- [x] Add `charts/qubership-jaeger/tests/proxy_authorization_test.sh`, following the style of
  `security_hardening_test.sh`. Cover these cases with `helm template`:
  - authorization disabled: no `jwt_authn` or `rbac` filter in the output;
  - `proxy.type=basic` with authorization enabled: no `jwt_authn` or `rbac` filter;
  - roles only, users only, and both: expected number of principals;
  - a custom multi-key `rolesClaim` and a URI-style claim name;
  - each validation failure: non-zero exit code and the expected message.
- [x] In the same script, extract `config.yaml` from the rendered Secret and run
  `envoy --mode validate` with the proxy image from the rendered deployment. The step fails on a deprecation warning.
- [x] Run the new script in `.github/workflows/integration-tests.yml` next to `security_hardening_test.sh`.
- [ ] Verify manually on a kind cluster with Keycloak. Record the result in the PR description.

| User                                  | Expected result                         |
| ------------------------------------- | --------------------------------------- |
| Has an allowed role                   | UI opens                                |
| No role, listed in `allowedUsers`     | UI opens                                |
| No role, not listed                   | 403 with the custom body on `/` and `/api/services` |
| Not signed in                         | Redirect to the IdP login page          |

### 6. Documentation

- [x] Add the new parameters and an example to the proxy section of `docs/installation.md`.
- [x] Add `docs/examples/auth/oauth2-authorization-values.yaml` with one Keycloak example.
- [x] Rewrite the OAuth2 section of `docs/examples/auth.md`. It lists `oauth2.issuerUrl`, `oauth2.allowedUsers`,
  `oauth2.allowedGroups`, and an `oauth2-config` secret, none of which exist in the chart.
- [x] Document the IdP side: how to add a realm role in Keycloak, and which claim rule ADFS needs.
- [x] Add a troubleshooting entry to `docs/troubleshooting.md`:
  - 401 `Jwt verification fails` or `Jwks remote fetch is failed`: check `jwksUri`, `issuer`, and `audiences`;
  - 403 for a user who was just granted a role: the role appears only in a new token, so sign out and sign in again.

## Changes made during implementation

- **`sourced_metadata` replaces `metadata` in the RBAC principals.** Envoy 1.35.2 loads `metadata` but reports it as
  deprecated and scheduled for removal.
- **The 403 body keeps the original reason.** Envoy also answers 403 when the token fails the audience check, so a
  fixed "not authorized" text would hide that cause.
- **`rolesClaim` has no `minItems` in the schema.** An empty list is valid when only `allowedUsers` is set. The
  render-time validation covers the case where roles are set without a claim path.
- **The filters were verified against a running Envoy 1.35.2 with locally signed tokens.** The full login flow against
  a live identity provider is still to be verified, see the open item in task 5.

## Known limitations

- A role change in the IdP takes effect when the user gets a new token, not immediately.
- An allowlist change restarts the query pod.
- Opaque (non-JWT) access tokens are not supported.
- The proxy image must be Envoy 1.35 or later when authorization is enabled.

## Out of scope

- Per-page or per-API authorization.
- `ext_authz` with an external policy service.
- Replacing Envoy with oauth2-proxy.
- Authorization for `proxy.type: basic`.
- Robot Framework tests against a live IdP.
