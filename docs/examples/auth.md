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

Enterprise OAuth2 integration with external providers.

```yaml title="oauth2-values.yaml"
--8<-- "examples/auth/oauth2-values.yaml"
```

**Key parameters:**
- `proxy.type: oauth2` - Enables OAuth2 authentication
- `oauth2.issuerUrl` - Identity provider endpoint
- `oauth2.allowedUsers` - Authorized user emails
- `oauth2.allowedGroups` - Authorized groups



## OAuth2 with a Custom CA Certificate

Use this setup when the identity provider has a self-signed certificate or a certificate signed by an internal CA.

```yaml title="oauth2-custom-ca-values.yaml"
--8<-- "examples/auth/oauth2-custom-ca-values.yaml"
```

**Key parameters:**
- `proxy.oauth2.tls.ca` - CA certificate in PEM format. The chart stores it in the `oauth2-idp-ca` secret
- `proxy.oauth2.tls.existingSecret` - Name of an existing secret with the CA certificate in the `ca-cert.pem` key.
  If specified, `proxy.oauth2.tls.ca` is ignored

**How the certificate is verified:**

Without these parameters, the proxy encrypts the connection to the identity provider but does not verify its
certificate. With one of them, the proxy checks two things and refuses the connection if either check fails:

- The certificate chain of the identity provider leads to the configured CA certificate.
- The certificate is issued for `proxy.oauth2.idpAddress`. A wildcard name such as `*.example.com` matches. If
  `idpAddress` is an IP address, the certificate must list that address.

For a self-signed certificate, pass the certificate itself as the CA certificate. To trust several CAs, put all the
certificates into one PEM file.

**Requirements:**
- `proxy.oauth2.authorizationEndpoint` and `proxy.oauth2.tokenEndpoint` start with `https://`. The chart fails to
  render if a CA certificate is set for an `http://` endpoint.
- The browser of the user must trust the certificate as well. The chart cannot configure that.

**Creating the secret:**

```bash
kubectl create secret generic corporate-ca -n <namespace> --from-file=ca-cert.pem=<path-to-ca-certificate>
```

**Replacing the CA certificate:**
- With `proxy.oauth2.tls.ca`, run `helm upgrade`. The chart restarts the query pod.
- With `proxy.oauth2.tls.existingSecret`, update the secret and restart the query pod yourself. The proxy reads the
  certificate only at startup.

## Usage

1. Choose authentication method
2. Update configuration parameters
3. Create required secrets:

```bash
# For OAuth2
kubectl create secret generic oauth2-config \
  --from-literal=client-secret=your-secret
```

4. Deploy with Helm:

```bash
helm install jaeger qubership-jaeger/qubership-jaeger -f auth-values.yaml
```
