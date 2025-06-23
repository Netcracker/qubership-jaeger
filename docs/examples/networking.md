# Networking Examples

Configure ingress, load balancing, and network policies for Jaeger components.

## Single Ingress

Route all traffic through one ingress controller.

```yaml title="collector-single-ingress-values.yaml"
--8<-- "examples/ingress/collector-single-ingress-values.yaml"
```

**Key parameters:**
- `collector.ingress.grpc` - gRPC endpoint for trace collection
- `collector.ingress.http` - HTTP endpoint for trace collection
- `query.ingress.tls` - TLS termination configuration
- Annotations for NGINX ingress controller

## Multiple Ingresses

Separate ingresses for different environments or teams.

```yaml title="collector-multiple-ingresses-values.yaml"
--8<-- "examples/ingress/collector-multiple-ingresses-values.yaml"
```

**Key parameters:**
- `ingressClassName` - Specific ingress controller
- Rate limiting annotations
- Authentication integration
- Multiple ingress definitions

## Custom Service Names

Use custom service names for better organization.

```yaml title="collector-custom-service-name-values.yaml"
--8<-- "examples/ingress/collector-custom-service-name-values.yaml"
```

**Key parameters:**
- `serviceName` - Custom Kubernetes service name
- `servicePort` - Specific port mapping
- Consistent naming across components

## Usage

1. Choose networking approach
2. Update hostnames and annotations
3. Configure TLS certificates if needed
4. Deploy with Helm:

```bash
helm install jaeger qubership-jaeger/qubership-jaeger -f networking-values.yaml
```