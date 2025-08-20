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
