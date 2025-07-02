# Configuration Examples

This section provides various configuration examples for different deployment scenarios. Each category has dedicated documentation with detailed examples and usage instructions.

## Authentication & Security

Secure your Jaeger deployment with various authentication methods:

**[Authentication Examples](examples/auth.md)**
- Basic Authentication - Simple username/password protection
- OAuth2 Integration - Enterprise SSO with external providers

## Storage Backends

### Cassandra Storage

Recommended for high-volume production deployments:

**[Cassandra Examples](examples/cassandra.md)**
- Simple Setup - Single-node development configuration
- Cluster Setup - Multi-node production deployment
- TLS Configuration - Secure connections with certificates
- Custom TTL - Data retention configuration
- Security Context - Pod security settings
- Custom Authenticators - Advanced authentication methods

### OpenSearch Storage

Powerful search capabilities and analytics:

**[OpenSearch Examples](examples/opensearch.md)**
- Simple Setup - Basic development configuration
- TLS Configuration - Secure connections
- Index Rollover - Automated index management
- Single Node - Minimal testing setup
- Custom Security - Pod security configurations

## Networking & Access

Configure external access and load balancing:

**[Networking Examples](examples/networking.md)**
- Single Ingress - Unified access point
- Multiple Ingresses - Environment separation
- Custom Service Names - Better organization

## Cloud Platforms

Platform-specific optimizations:

**[Cloud Examples](examples/cloud.md)**
- AWS Configuration - OpenSearch Service integration
- Load Balancer setup - NLB/ALB configurations
- IAM/RBAC - Service account permissions

## General Configuration

Common deployment scenarios and utilities:

**[General Examples](examples/general.md)**
- Agent with Cassandra - Complete tracing setup
- Custom Images - Private registry usage
- ElasticSearch Storage - Alternative backend
- High Availability - Production-ready HA setup
- HotROD Demo - Sample application with traces
- Integration Tests - Automated validation

## Quick Start

1. **Choose your scenario** from the categories above
2. **Follow the dedicated guide** for detailed instructions
3. **Download example values** from the linked pages
4. **Deploy with Helm**:

```bash
helm repo add qubership-jaeger https://charts.qubership.org
helm install jaeger qubership-jaeger/qubership-jaeger -f your-values.yaml
```

## Common Configuration Patterns

Most examples support these standard parameters:

- **Resources** - CPU/memory limits and requests
- **Replicas** - Pod scaling for high availability
- **Storage** - Backend selection and configuration
- **Security** - TLS, authentication, authorization
- **Monitoring** - Metrics and observability

For detailed parameter reference, see the [Installation Guide](installation.md).
