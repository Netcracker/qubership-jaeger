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

## Usage

1. Choose your deployment scenario
2. Update service endpoints and credentials
3. Configure cloud-specific annotations
4. Set up IAM/RBAC permissions
5. Deploy with Helm:

```bash
helm install jaeger qubership-jaeger/qubership-jaeger -f values.yaml
```
