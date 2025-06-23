# OpenSearch Storage Examples

OpenSearch/Elasticsearch backend for flexible search and analytics capabilities.

## Simple OpenSearch Setup

Basic configuration for development environments.

```yaml title="opensearch-simple-values.yaml"
--8<-- "examples/opensearch/opensearch-simple-values.yaml"
```

**Key parameters:**
- `elasticsearch.client.url` - OpenSearch endpoint
- `indexCleaner.install: true` - Enables automatic index cleanup
- `scheme: https` - Secure connection

## OpenSearch with TLS

Secure connection with custom certificates.

```yaml title="opensearch-tls-with-certificates-values.yaml"
--8<-- "examples/opensearch/opensearch-tls-with-certificates-values.yaml"
```

**Key parameters:**
- `tls.enabled: true` - Enables TLS verification
- `skipHostVerify: false` - Strict certificate validation
- `tls.secretName` - Kubernetes secret with certificates

## OpenSearch with Rollover

Automatic index management for large deployments.

```yaml title="opensearch-rollover-values.yaml"
--8<-- "examples/opensearch/opensearch-rollover-values.yaml"
```

**Key parameters:**
- `indexCleaner.numberOfDays: 7` - Retain 7 days of data
- `rollover.conditions.maxAge: "1d"` - Daily index rotation
- `rollover.conditions.maxSize: "10gb"` - Size-based rotation

## OpenSearch Single Node

Minimal setup for testing.

```yaml title="opensearch-one-node-values.yaml"
--8<-- "examples/opensearch/opensearch-one-node-values.yaml"
```

**Key parameters:**
- `scheme: http` - Non-secure connection for testing
- `indexCleaner.install: false` - Disabled for testing
- Minimal resource allocation

## OpenSearch with Insecure TLS

TLS with certificate verification disabled.

```yaml title="opensearch-tls-with-insecure-skip-verify-values.yaml"
--8<-- "examples/opensearch/opensearch-tls-with-insecure-skip-verify-values.yaml"
```

**Key parameters:**
- `tls.enabled: true` - Enables TLS
- `skipHostVerify: true` - Disables certificate validation
- Useful for self-signed certificates

## OpenSearch with Predefined Secret

Use existing Kubernetes secret for TLS certificates.

```yaml title="opensearch-tls-with-predefined-secret-values.yaml"
--8<-- "examples/opensearch/opensearch-tls-with-predefined-secret-values.yaml"
```

**Key parameters:**
- `tls.secretName` - Existing Kubernetes secret
- Pre-configured TLS certificates
- External certificate management

## OpenSearch Custom Security Context

Configure security context for OpenSearch pods.

```yaml title="opensearch-custom-secuirty-context.yaml"
--8<-- "examples/opensearch/opensearch-custom-secuirty-context.yaml"
```

**Key parameters:**
- `securityContext` - Pod security settings
- `runAsUser` - User ID for container execution
- `fsGroup` - File system group ownership

## Usage

1. Update OpenSearch connection details
2. Configure authentication credentials
3. Deploy with Helm:

```bash
helm install jaeger qubership-jaeger/qubership-jaeger -f values.yaml
```
