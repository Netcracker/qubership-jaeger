# Cloud Provider Examples

Optimized configurations for major cloud platforms.

## AWS Deployment

Complete AWS setup with managed services.

```yaml title="aws-values.yaml"
--8<-- "examples/public-clouds/aws-values.yaml"
```

**Key parameters:**
- AWS OpenSearch Service endpoint
- Network Load Balancer (NLB) for collector
- Application Load Balancer (ALB) for query UI
- IAM roles for service accounts (IRSA)
- Multi-AZ deployment with pod anti-affinity

## High Availability Deployment

Multi-replica setup for production environments.

```yaml title="ha-deployment-value.yaml"
--8<-- "examples/ha-deployment-value.yaml"
```

**Key parameters:**
- Multiple replicas for each component
- Resource limits for production workloads
- Anti-affinity rules for high availability
- Load balancing configuration

## Custom Images

Use custom Docker images for Jaeger components.

```yaml title="custom-images.yaml"
--8<-- "examples/custom-images.yaml"
```

**Key parameters:**
- Custom image repositories
- Specific image tags
- Image pull policies
- Private registry configuration

## Agent with Cassandra

Deploy Jaeger agent alongside Cassandra storage.

```yaml title="agent-cassandra-values.yaml"
--8<-- "examples/agent-cassandra-values.yaml"
```

**Key parameters:**
- Jaeger agent configuration
- Cassandra storage backend
- Agent-to-collector communication
- DaemonSet deployment

## HotRod Demo Application

Deploy HotRod demo application for testing.

```yaml title="hotord-example-values.yaml"
--8<-- "examples/hotord-example-values.yaml"
```

**Key parameters:**
- HotRod application deployment
- Service configuration
- Ingress setup
- Trace generation for testing

## Integration Tests

Configuration for running integration tests.

```yaml title="integration-tests-values.yaml"
--8<-- "examples/integration-tests-values.yaml"
```

**Key parameters:**
- Test configuration
- Service accounts and RBAC
- Test execution environment
- Validation parameters

## Elasticsearch Example

Legacy Elasticsearch configuration example.

```yaml title="elasticsearch-example-values.yaml"
--8<-- "examples/elasticsearch-example-values.yaml"
```

**Key parameters:**
- Elasticsearch backend configuration
- Index management
- Authentication setup
- Legacy compatibility

## Usage

1. Choose your deployment scenario
2. Update service endpoints and credentials
3. Configure cloud-specific annotations
4. Set up IAM/RBAC permissions
5. Deploy with Helm:

```bash
helm install jaeger qubership-jaeger/qubership-jaeger -f values.yaml
```

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
