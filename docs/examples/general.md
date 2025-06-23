# General Configuration Examples

Various general-purpose configuration examples for different deployment scenarios.

## Agent with Cassandra

Jaeger agent deployment with Cassandra storage backend.

```yaml title="agent-cassandra-values.yaml"
--8<-- "examples/agent-cassandra-values.yaml"
```

**Key parameters:**
- `jaeger.storage.type: cassandra` - Uses Cassandra as storage backend
- `cassandraSchemaJob.mode: prod` - Production replication strategy
- `ttl.trace: 1209600` - Traces retained for 2 weeks
- `ttl.dependencies: 0` - Dependencies stored forever
- `hotrod.install: true` - Deploys demo application for testing

## Custom Docker Images

Override default images with custom or specific versions.

```yaml title="custom-images.yaml"
--8<-- "examples/custom-images.yaml"
```

**Key parameters:**
- `collector.image` - Custom Jaeger collector image
- `query.image` - Custom Jaeger query image
- `proxy.image` - Custom Envoy proxy image
- `cassandraSchemaJob.image` - Custom schema migration image
- `integrationTests.image` - Custom integration tests image

**Use cases:**
- Using private registry images
- Pinning to specific versions
- Custom builds with patches

## ElasticSearch Storage

Basic ElasticSearch configuration as storage backend.

```yaml title="elasticsearch-example-values.yaml"
--8<-- "examples/elasticsearch-example-values.yaml"
```

**Key parameters:**
- `jaeger.storage.type: elasticsearch` - Uses ElasticSearch storage
- `elasticsearch.client.url` - ElasticSearch service endpoint
- `elasticsearch.client.scheme: https` - Secure connection
- `elasticsearch.indexCleaner.install: true` - Automated index cleanup

## High Availability Deployment

Production-ready HA configuration with multiple replicas and anti-affinity.

```yaml title="ha-deployment-value.yaml"
--8<-- "examples/ha-deployment-value.yaml"
```

**Key parameters:**
- `collector.replicas: 2` - Multiple collector instances
- `query.replicas: 2` - Multiple query instances
- `affinity.podAntiAffinity` - Spreads pods across nodes
- `requiredDuringSchedulingIgnoredDuringExecution` - Hard anti-affinity rule

**Benefits:**
- Fault tolerance
- Load distribution
- Zero-downtime updates

## HotROD Demo Application

Demo application deployment for trace generation and testing.

```yaml title="hotord-example-values.yaml"
--8<-- "examples/hotord-example-values.yaml"
```

**Key parameters:**
- `hotrod.install: true` - Deploys HotROD demo app
- `hotrod.ingress.install: true` - Exposes demo via ingress
- `hotrod.ingress.host` - External hostname
- Uses ElasticSearch as storage backend

**Purpose:**
- Generate sample traces
- Verify Jaeger installation
- Demo distributed tracing

## Integration Tests

Automated testing configuration for validating Jaeger deployment.

```yaml title="integration-tests-values.yaml"
--8<-- "examples/integration-tests-values.yaml"
```

**Key parameters:**
- `integrationTests.install: true` - Enables integration tests
- `integrationTests.tags: "smokeORha"` - Test suite selection
- `integrationTests.generateCount: 10` - Number of test traces
- `integrationTests.waitingTime: 500ms` - Delay between operations
- `statusProvisioner.enabled: true` - Deployment status reporting

**Security context:**
- `runAsUser: 2000` - Non-root user execution
- `runAsNonRoot: true` - Security enforcement
- `allowPrivilegeEscalation: false` - Prevents privilege escalation

## Deployment Scenarios

**Production:**
- HA deployment with multiple replicas
- External storage (Cassandra/OpenSearch)
- TLS encryption and authentication
- Resource limits and monitoring

**Development:**
- Single replica deployment
- In-memory or simple storage
- No authentication required
- Minimal resource allocation

**Testing:**
- HotRod demo application
- Integration test suite
- Temporary storage
- Automated validation
