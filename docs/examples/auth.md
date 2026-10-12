# Authentication Examples

Secure your Jaeger deployment with authentication and authorization.

## Basic Authentication

Simple username/password authentication.

```yaml title="basic-auth-values.yaml"
--8<-- "examples/auth/basic-auth-values.yaml"
```

**Key parameters:**
- `proxy.type: basic` - Enables basic authentication
- `proxy.basic.users` - base64 encoded credentials
- Proxy acts as authentication gateway

**Creating credentials:**
```bash
# Encode username:password
echo -n "admin:admin" | base64
# Output: YWRtaW46YWRtaW4=
```

## OAuth2 Authentication

Log in through an external identity provider, for example Keycloak.

```yaml title="oauth2-values.yaml"
--8<-- "examples/auth/oauth2-values.yaml"
```

**Key parameters:**
- `proxy.type: oauth2` - Enables OAuth2 authentication
- `proxy.oauth2.tokenEndpoint` - Token endpoint of the identity provider
- `proxy.oauth2.authorizationEndpoint` - Endpoint that users are redirected to for login
- `proxy.oauth2.clientId` and `proxy.oauth2.clientToken` - Client ID and client secret registered in the identity
  provider
- `proxy.oauth2.idpAddress` and `proxy.oauth2.idpPort` - Host and port of the identity provider

Register `https://<jaeger-host>/callback` as a valid redirect URI of the client.

Without the authorization check, every user who can log in to the identity provider can open Jaeger UI.

## OAuth2 Authorization

Restrict Jaeger UI to selected users. The check applies to the whole UI and to the query API behind it.

```yaml title="oauth2-authorization-values.yaml"
--8<-- "examples/auth/oauth2-authorization-values.yaml"
```

**Key parameters:**
- `proxy.oauth2.authorization.enabled: true` - Enables the authorization check
- `proxy.oauth2.authorization.jwksUri` - JWKS endpoint used to verify the token signature. It must be served by
  `proxy.oauth2.idpAddress`
- `proxy.oauth2.authorization.rolesClaim` - Path to the roles or groups claim, one key per list item
- `proxy.oauth2.authorization.allowedRoles` - Roles or groups that grant access
- `proxy.oauth2.authorization.userClaim` - Claim that identifies the user
- `proxy.oauth2.authorization.allowedUsers` - Users that get access regardless of their roles

**How access is decided:**

A user gets access if the access token carries one of `allowedRoles`, or if the user is in `allowedUsers`. Use
`allowedUsers` for individual users who are not members of an allowed group. Other users get a 403 response after the
login.

Values are compared exactly and case-sensitively. Set at least one of `allowedRoles` and `allowedUsers`, otherwise the
chart fails to render.

**Requirements:**
- The access token is a JWT. Opaque access tokens are not supported.
- The proxy image is Envoy 1.35 or later. The chart default meets this requirement.

**Roles claim by identity provider:**

<!-- markdownlint-disable line-length -->
| Identity provider and source | `rolesClaim`                            | Setup in the identity provider                                        |
| ---------------------------- | --------------------------------------- | --------------------------------------------------------------------- |
| Keycloak realm roles         | `[realm_access, roles]`                 | Create a realm role and assign it to the user                         |
| Keycloak client roles        | `[resource_access, <client-id>, roles]` | Create a role in the client and assign it to the user                 |
| Keycloak groups              | `[groups]`                              | Add a Group Membership mapper with the token claim name `groups`      |
| ADFS groups or roles         | The claim name from the token           | Add an issuance transform rule that sends group membership as a claim |
<!-- markdownlint-enable line-length -->

To find the claim names that your identity provider sends, decode the payload of an access token. After a login, the
browser keeps the token in the `BearerToken` cookie.

```bash
echo '<access-token>' | cut -d. -f2 | tr '_-' '/+' | base64 -d
```

**Changing access:**
- A role granted or revoked in the identity provider takes effect when the user gets a new token. Ask the user to open
  `/signout` and log in again.
- A change of `allowedRoles` or `allowedUsers` takes effect after `helm upgrade`, which restarts the query pod.

## Usage

1. Choose the authentication method.
2. Copy the matching example and replace the endpoints, the credentials, and the allowed roles and users.
3. Deploy with Helm:

```bash
helm install jaeger qubership-jaeger/qubership-jaeger -f auth-values.yaml
```
