# Qubership Jaeger

Welcome to **Qubership Jaeger** - a production-ready Helm chart for deploying [Jaeger](https://github.com/jaegertracing/jaeger) distributed tracing system in Kubernetes and OpenShift environments.

## What is Jaeger?

Jaeger is an open-source, end-to-end distributed tracing system that helps you monitor and troubleshoot transactions in complex distributed systems. It allows you to:

- **Monitor distributed transactions** - Track requests as they flow through multiple services
- **Identify performance bottlenecks** - Find slow components and optimize your system
- **Troubleshoot microservices** - Understand service dependencies and failure patterns
- **Analyze system behavior** - Get insights into your distributed architecture

## What is Qubership Jaeger?

Qubership Jaeger is a comprehensive Helm chart that simplifies the deployment and management of Jaeger in cloud-native environments. It provides:

### Key Features

- **Production-ready configuration** - Optimized settings for enterprise environments
- **Multiple storage backends** - Support for Cassandra, OpenSearch, and ElasticSearch
- **High availability** - Multi-replica deployments with load balancing
- **Security features** - TLS encryption, authentication, and authorization options
- **Cloud platform support** - Works on AWS, Azure, Google Cloud, and on-premises
- **Monitoring integration** - Built-in Prometheus metrics and Grafana dashboards
- **Flexible configuration** - Extensive customization options via Helm values

### Architecture Components

The chart deploys the following Jaeger components:

- **Collector** - Receives tracing data from applications
- **Query** - Provides Web UI and API for trace retrieval
- **Readiness Probe** - Custom health checking component for storage backends
- **Status Provisioner** - Deployment status management

### Storage Options

- **Cassandra** - Recommended for high-volume production deployments
- **OpenSearch/ElasticSearch** - Alternative storage with powerful search capabilities
- **Cloud services** - AWS OpenSearch, managed databases

## Quick Start

### Prerequisites

- Kubernetes 1.21+ or OpenShift 4.10+
- Helm 3.0+
- Storage backend (Cassandra, OpenSearch, or ElasticSearch)

### Basic Installation

```bash
# Add the repository (if available)
helm repo add qubership-jaeger <repository-url>
helm repo update

# Install with Cassandra storage
helm install jaeger qubership-jaeger/qubership-jaeger \
  --set jaeger.storage.type=cassandra \
  --set cassandra.host=<your-cassandra-host>
```

### Example Configuration

```yaml
jaeger:
  serviceName: jaeger
  storage:
    type: "cassandra"

collector:
  replicas: 3
  resources:
    requests:
      cpu: 200m
      memory: 256Mi

query:
  resources:
    requests:
      cpu: 100m
      memory: 128Mi

cassandra:
  host: "cassandra-cluster.default.svc.cluster.local"
  port: 9042
  datacenter: "datacenter1"
```

## Documentation Structure

This documentation is organized to help you at different stages of your Jaeger journey:

- **Installation** - Step-by-step deployment guides for various scenarios
- **Configuration** - Examples and best practices for different use cases
- **Operations** - Maintenance, monitoring, and troubleshooting guides
- **Integrations** - Connecting with observability platforms and external systems

## Getting Help

- **Installation Issues** - Check the [Installation Guide](installation.md)
- **Runtime Problems** - See [Troubleshooting](troubleshooting.md)
- **Performance Tuning** - Review [Performance Guide](performance.md)
- **Monitoring Setup** - Follow [Observability Guide](observability.md)

## Development

For developers working on this project:

### Code Quality

Before pushing commits and creating PRs, run linters and tests:

```bash
# SuperLinter
docker run \
  -e RUN_LOCAL=true \
  -e DEFAULT_BRANCH=$(git rev-parse --abbrev-ref HEAD) \
  --env-file .github/super-linter.env \
  -v ${PWD}:/tmp/lint \
  --rm \
  ghcr.io/super-linter/super-linter:slim-$(sed -nE 's#.*uses:\s+super-linter/super-linter/slim@([^\s]+).*#\1#p' .github/workflows/super-linter.yaml)
```

### Documentation Development

This documentation site is built with MkDocs Material:

```bash
# Setup environment
python -m venv venv
source venv/bin/activate
pip install -r requirements_mkdocs.txt

# Serve locally
mkdocs serve --dev-addr=127.0.0.1:8001
# Open: http://127.0.0.1:8001/qubership-jaeger/

# Build site
mkdocs build --clean
```

## Application and Components

### Core Jaeger Application

Based on the official [Jaeger project](https://github.com/jaegertracing/jaeger), this chart provides enterprise-ready deployment of the complete Jaeger distributed tracing system.

### Included Components

This Helm chart includes the following components:

- **[Jaeger Collector, Query, Agent](https://github.com/jaegertracing/jaeger)** - Core Jaeger components
- **[Readiness Probe](https://github.com/Netcracker/qubership-jaeger/tree/main/readiness-probe)** - Custom health check utility for storage backends
- **[Deployment Status Provisioner](https://github.com/Netcracker/qubership-deployment-status-provisioner)** - Kubernetes deployment status management

### Supported Storage Backends

- **Cassandra** - Recommended for high-volume production environments
- **OpenSearch** - Modern alternative with advanced search capabilities
- **ElasticSearch** - Legacy support for existing deployments

## Contributing

This project is part of the Qubership platform. For contributions and development guidelines, please refer to the main repository.

## License

This project is licensed under the Apache License 2.0. See the [LICENSE](https://github.com/Netcracker/qubership-jaeger/blob/main/LICENSE) file for details.
