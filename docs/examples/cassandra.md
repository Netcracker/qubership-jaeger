# Cassandra Storage Examples

Cassandra is the recommended storage backend for high-volume production deployments.

## Simple Cassandra Setup

Basic single-node configuration for development or testing.

```yaml title="cassandra-simple-values.yaml"
--8<-- "examples/cassandra/cassandra-simple-values.yaml"
```

**Key parameters:**
- `cassandraSchemaJob.mode: prod` - Uses NetworkReplicationStrategy for production
- `cassandraSchemaJob.host` - Cassandra service endpoint
- `hotrod.install: true` - Deploys test trace generator

## Cassandra Cluster Setup

Production-ready cluster configuration with replication.

```yaml title="cassandra-cluster-values.yaml"
--8<-- "examples/cassandra/cassandra-cluster-values.yaml"
```

**Key parameters:**
- `replicationFactor: 3` - Data replicated across 3 nodes
- `collector.replicas: 3` - Multiple collector instances
- Resource limits for production workloads

## Cassandra with TLS

Secure connection to Cassandra cluster.

```yaml title="cassandra-tls-with-certificates-values.yaml"
--8<-- "examples/cassandra/cassandra-tls-with-certificates-values.yaml"
```

**Key parameters:**
- `tls.enabled: true` - Enables TLS encryption
- `tls.secretName` - Kubernetes secret with certificates
- `tls.serverName` - Certificate validation hostname

## Cassandra with TLS (Predefined Secret)

TLS configuration using existing Kubernetes secret.

```yaml title="cassandra-tls-with-predefined-secret-values.yaml"
--8<-- "examples/cassandra/cassandra-tls-with-predefined-secret-values.yaml"
```

**Key parameters:**
- `tls.enabled: true` - Enables TLS encryption
- `tls.existingSecret` - References existing Kubernetes secret
- `mode: prod` - Production replication strategy
- Assumes TLS secret already exists in cluster

## Custom TTL Configuration

Configure data retention periods.

```yaml title="cassandra-custom-ttl-values.yaml"
--8<-- "examples/cassandra/cassandra-custom-ttl-values.yaml"
```

**Key parameters:**
- `traceTTL: 172800` - Traces retained for 2 days
- `dependenciesTTL: 86400` - Dependencies retained for 1 day
- TTL values in seconds

## Custom Security Context

Configure security context for Cassandra pods.

```yaml title="cassandra-custom-security-context.yaml"
--8<-- "examples/cassandra/cassandra-custom-security-context.yaml"
```

**Key parameters:**
- `securityContext` - Pod security settings
- `runAsUser` - User ID for container execution
- `fsGroup` - File system group ownership

## Custom Authenticators

Configure custom authentication methods for Cassandra.

```yaml title="cassandra-custom-allowed-authenticators.yaml"
--8<-- "examples/cassandra/cassandra-custom-allowed-authenticators.yaml"
```

**Key parameters:**
- `authenticator` - Authentication mechanism
- `authorizer` - Authorization mechanism
- Custom authentication configuration

## Usage

1. Download the desired configuration file
2. Update `<cloud_dns_name>` with your domain
3. Update Cassandra credentials
4. Deploy with Helm:

```bash
helm install jaeger qubership-jaeger/qubership-jaeger -f values.yaml
```