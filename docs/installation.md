# Installation Notes

This chapter describes the procedure to deploy the Jaeger application in the Kubernetes/OpenShift project.
The deployment includes a collector to collect the data, a query for UI purposes in a query pod
for tracing the query.

## Prerequisites

This section describes the prerequisites to deploy Jaeger in the Cloud.

### Common

* Kubernetes 1.21+ or OpenShift 4.10+
* kubectl 1.21+ or oc 4.10+ CLI
* Helm 3.0+

### Storage

#### Cassandra Storage

**Note:** This section is applicable only to cases when Cassandra is used as a store.

Supported Cassandra versions:

* 4.x (recommended)
* 3.x

Depending on the configuration of your Cassandra cluster you can configure different replication strategies
for Jaeger's data.

If your Cassandra cluster has **2 or more nodes** in the cluster, you can use data replication. It can be configured
using the deployment parameter:

```yaml
cassandraSchemaJob:
  mode: prod
```

**Note:** If you want, with 2 or more Cassandra nodes you can use a SimpleStrategy without data replication.

If your Cassandra cluster has **only 1 node**, you can use a SimpleStrategy without data replication.
It can be configured using the deployment parameter:

```yaml
cassandraSchemaJob:
  mode: test
```

**Warning!** The `mode: prod` **can't be used** if you have **only 1** Cassandra node. Jaeger won't allow to create
of a schema and other Jaeger pods won't start with this configuration.


#### OpenSearch/ElasticSearch

**Note:** This section applies only to cases when OpenSearch/ElasticSearch is used as a store.

Selecting between OpenSearch and ElasticSearch we recommended using **OpenSearch**.

Supported OpenSearch versions:

* 2.x (recommended)
* 1.x

Supported ElasticSearch versions:

* 7.x
* 6.x
* 5.x


### Kubernetes

To deploy Jaeger in the Kubernetes/OpenShift you must have at least a namespace admin role.
You should have at least permissions like the following:

```yaml
kind: Role
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  namespace: <jaeger-namespace>
  name: deploy-user-role
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
```

**Note:** It's not a role that you have to create. It's just an example with a minimal list of permissions.

For Kubernetes 1.25+, it is recommended to deploy Jaeger using `baseline` PSS. Before deploying please make sure
that your namespace has the following labels:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: <name>
  labels:
    pod-security.kubernetes.io/enforce: baseline
    pod-security.kubernetes.io/enforce-version: latest
```

For Kubernetes 1.25+ if `restricted` PSS is specified on namespace using
`pod-security.kubernetes.io/enforce: restricted`, then it is necessary to configure
`securityContext` and `containerSecurityContext` appropriately.

At the pod level, `runAsNonRoot: true` and `seccompProfile.type: "RuntimeDefault"` will be added automatically.
At the container level, `allowPrivilegeEscalation: false` and `capabilities.drop: - ALL` will be added automatically.
It is recommended not to override these values because Kubernetes `restricted`` PSS expects these values.


### Azure

| Azure Managed Service                                                                           | Jaeger support |
| ----------------------------------------------------------------------------------------------- | -------------- |
| [Azure CosmosDB (Cassandra)](https://azure.microsoft.com/en-in/products/cosmos-db)              | ❌ Not Support  |
| [Azure Cassandra](https://azure.microsoft.com/en-in/products/managed-instance-apache-cassandra) | ❔ Not Verified |
| Azure OpenSearch                                                                                | - N/A          |

We almost didn't verify Jaeger working with Azure managed services. But we know about some GitHub issues related
to supporting Azure managed services. So we know that Jaeger doesn't support Azure CosmosDB now. GitHub issue
[Support PaaS Cassandra - Create Schema on Azure CosmosDB](https://github.com/jaegertracing/jaeger/issues/2468).

There is no Azure managed OpenSearch. You can find only custom solutions in the Azure marketplace from other vendors.


### AWS

| AWS Managed Service       | Jaeger support |
| ------------------------- | -------------- |
| AWS Keyspaces (Cassandra) | ❌ Not Support  |
| AWS OpenSearch            | ✅ Support      |

Jaeger doesn't support AWS Keyspaces because Keyspaces doesn't allow to creation of frozen structures and custom
structures. GitHub issue
[Support for AWS managed Cassandra (aka AWS MCS, Amazon Keyspaces)](https://github.com/jaegertracing/jaeger/issues/2294).

But Jaeger supports AWS OpenSearch as a managed service. Recommendation for AWS OpenSearch:

* OpenSearch 1.x and 2.x both supports
* Recommended use OpenSearch with resources not less than:
  * CPU: >= 2 cores
  * Memory: >= 4-8 GB
* To run Jaeger with AWS OpenSearch recommended using flavors not less than:
  * r5.large.search
  * m4.large.search
  * c6g.large.search
  * c5.large.search
  * c4.large.search


### Google

| Google Managed Service | Jaeger support |
| ---------------------- | -------------- |
| Google Cassandra       | - N/A          |
| Google OpenSearch      | - N/A          |

Google has no officially managed Cassandra, OpenSearch or ElasticSearch. You can find only custom solutions
in the Google marketplace from other vendors.


## Best practices and recommendations

### HWE

The minimal hardware values with which Jaeger can start:

Collector:

| Component | CPU Requests | Memory Requests | CPU Limits | Memory Limits |
| --------- | ------------ | --------------- | ---------- | ------------- |
| collector | 50m          | 64Mi            | 100m       | 128Mi         |
| query     | 100m         | 64Mi            | 150m       | 128Mi         |

For more information about Jaeger's performance, refer to the [Jaeger Service Performance Monitoring](performance.md)
section in the _Cloud Platform Monitoring Guide_.

**Note**: The above resources are required for starting, not for working under load. For production, the resources
should be increased, also if needed, the collector can be scaled horizontally.

Disk space for storing Jaeger traces might be calculated in several ways:

* First of all, trace might contain more than one span, it depends on how many services (APIs) call each request.
  If you are able to calculate a number of spans as:
  
  ```txt
  Number of spans per second = number traces in your system(requests) * number of spans per trace 
  ```

  Please note not all requests on prod env are sent traces in Jaeger, so you only need to count the traced requests.
  After that, you are able to calculate the total number of spans as:

* If you have installed Jaeger on pre-production or production env you are able to check the number of spans per second
  with Jaeger self metrics. See the "span creation rate" panel on the "Jaeger-overview" Grafana dashboard.
  Or you can calculate the value in Prometheus\/VMUI:

  ```Promql
  sum(rate(jaeger_reporter_spans[1m]))
  ```

  or

  ```Promql
  sum(rate(jaeger_collector_spans_received_total{service="jaeger-collector"}[1m]))/60
  ```

After that, you can calculate the total number of spans:

```txt
Total number of spans = Number of spans per second * Retention period in seconds
```

**Warning!** TTL for Jaeger's Cassandra tables **can't be changed** during update!
You must set correct TTL values during first deploy! If you didn't do it, please read the
[Maintenance: Change Cassandra TTL](maintenance.md#change-cassandra-ttl).

To find the retention period see `ttl` for [Cassandra](#cassandra) and `numberOfDays` for
[Elasticsearch\/Opensearch](#index-cleaner).

We have made measurements and found that each 100000 spans requires about 90 Megabytes of disk space
or 0.9kb per span.
Also, 30% of the additional disk space is needed for storage maintenance (e.g. retention).
That means you need to allocate about 120 Megabytes of disk space for each 100k spans.

Please note that Jaeger by default trace only 1% of all traces(probabilistic sampler type).

```txt
Disk space usage(in Megabytes) = Total number of spans * 0.0009 * Probabilistic coefficient
```

For example:

Services generate 1500 spans but Jaeger will receive 10%(150 spans per second) and traces will be stored for 7 days.
So the total number of spans will be:

```txt
1500 * 0.1 * 86400(seconds per day) * 7 = 90 720 000
```

And disk space usage will be:

```txt
90 720 000 * 0.0009 = 81648Mb or (~80Gb)
80Gb + 30% = 105Gb
```

### TLS

Support matrix Jaeger as third-party:

| Connection                 | Support TLS   |
| -------------------------- | ------------- |
| Client to Collector        | ✅ Support     |
| Collector/Query to Storage | ✅ Support     |
| Browser to UI              | ❌ Not Support |


## Parameters

This section describes parameters that can be used to deploy Jaeger and its components in the Cloud.

### Jaeger

It's a common section that contains some generic parameters.

All parameters in the table below should be specified under the key:

```yaml
jaeger:
  ...
```

<!-- markdownlint-disable line-length -->
| Parameter                       | Type    | Mandatory | Default value | Description                                                                            |
| ------------------------------- | ------- | --------- | ------------- | -------------------------------------------------------------------------------------- |
| `storage.type`                  | string  | yes       | cassandra     | Type of storage, available values: `cassandra` and `elasticsearch`                     |
| `serviceName`                   | string  | no        | jaeger        | Jaeger base deployment or service name                                                 |
| `prometheusMonitoring`          | boolean | no        | true          | Install ServiceMonitors that allow Monitoring collect metrics from Jaeger's components |
| `prometheusMonitoringDashboard` | boolean | no        | true          | Install the GrafanaDashboard that visualize metrics collect by Monitoring              |
<!-- markdownlint-enable line-length -->

Examples:

```yaml
jaeger:
  # Use to select type of storage
  storage:
    type: cassandra

  serviceName: jaeger

  # Use to enable monitoring for Jaeger
  prometheusMonitoring: true
  prometheusMonitoringDashboard: true
```


### Collector

`jaeger-collector` receives traces, runs them through a processing pipeline for validation and clean-up/enrichment,
and stores them in a storage backend. Jaeger comes with built-in support for several storage backends,
as well as an extensible plugin framework for implementing custom storage plugins.

All parameters in the table below should be specified under the key:

```yaml
collector:
  install: true
  ...
```

<!-- markdownlint-disable line-length -->
| Parameter                  | Type                                                                                                                          | Mandatory | Default value                                                           | Description                                                                                                                           |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | --------- | ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `install`                  | boolean                                                                                                                       | no        | true                                                                    | Allows enabling/disabling creating collector deployment                                                                               |
| `image`                    | string                                                                                                                        | no        | -                                                                       | Docker image to use for a collector container                                                                                         |
| `name`                     | string                                                                                                                        | no        | collector                                                               | The name of a microservice to deploy with                                                                                             |
| `imagePullPolicy`          | string                                                                                                                        | no        | IfNotPresent                                                            | `imagePullPolicy` for a container and the tag of the image affects when the `kubelet` attempts to pull (download) the specified image |
| `imagePullSecrets`         | object                                                                                                                        | no        | []                                                                      | Keys to access the private registry                                                                                                   |
| `replicas`                 | integer                                                                                                                       | no        | 1                                                                       | Count of replicas for the collector                                                                                                   |
| `zipkinPort`               | integer                                                                                                                       | no        | 9411                                                                    | Specifies the port of the Zipkin service                                                                                              |
| `cmdlineParams`            | object                                                                                                                        | no        | []                                                                      | Collector-related cmd line opts to be configured on the concerned components                                                          |
| `extraEnv`                 | object                                                                                                                        | no        | []                                                                      | Collector-related extra env vars to be configured on the concerned components                                                         |
| `samplingConfig`           | boolean                                                                                                                       | no        | false                                                                   | Enabling/disabling `SAMPLING_STRATEGIES_FILE`                                                                                         |
| `nodeSelector`             | map                                                                                                                           | no        | {}                                                                      | Defining which Nodes the Pods are scheduled on                                                                                        |
| `tolerations`              | [core/v1.Toleration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core)                 | no        | {}                                                                      | Allows the pods to schedule onto nodes with matching taints                                                                           |
| `resources`                | object                                                                                                                        | no        | {requests: {cpu: 100m, memory: 100Mi}, limits: {cpu: 1, memory: 200Mi}} | Describes computing resource requests and limits for single Pods                                                                      |
| `securityContext`          | [core/v1.PodSecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#podsecuritycontext-v1-core) | no        | {}                                                                      | Describes pod-level security attributes                                                                                               |
| `containerSecurityContext` | [core/v1.SecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#securitycontext-v1-core)       | no        | {}                                                                      | Holds container-level security attributes                                                                                             |
| `priorityClassName`        | string                                                                                                                        | no        | `-`                                                                     | PriorityClassName assigned to the Pods to prevent them from evicting.                                                                 |
| `tlsConfig`                | [TLSConfig](#tlsconfig)                                                                                                       | no        | `{}`                                                                    | Contains TLS settings for collector.                                                                                                  |
| `labels`                   | map                                                                                                                           | no        | {}                                                                      | Labels for collector.                                                                                                                 |
| `annotations`              | map                                                                                                                           | no        | {}                                                                      | Annotations for collector.                                                                                                            |
<!-- markdownlint-enable line-length -->

Example:

**Note:** It's just an example of a parameter's format, not recommended parameters.

```yaml
collector:
  install: true
  replicas: 1
  name: collector
  image: jaegertracing/jaeger-collector:1.62.0

  imagePullPolicy: IfNotPresent
  imagePullSecrets:
    - name: jaeger-pull-secret

  resources:
    requests:
      cpu: 100m
      memory: 100Mi
    limits:
      cpu: 1000m
      memory: 200m
  securityContext:
    runAsUser: 2000
    fsGroup: 2000
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containerSecurityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL

  zipkinPort: 9411
  samplingConfig: true

  ingress:
    ...

  cmdlineParams:
    - '--cassandra.max-retry-attempts=10'
  extraEnv:
    - name: ES_TIMEOUT
      value: 30s

  nodeSelector:
    node-role.kubernetes.io/worker: worker
  tolerations:
    - key: key1
      operator: Equal
      value: value1
      effect: NoSchedule
  priorityClassName: priority-class
  tlsConfig: {}
  annotations:
    example.annotation/key: example-annotation-value
  labels:
    example.label/key: example-label-value
```


#### Ingress

This section describes Ingress configuration for `jaeger-collector`.

Two ingresses are created separately for `http` and `grpc` protocols. Parameters must be configured for both the
protocols under `collector.ingress` section.

```yaml
collector:
  ingress:
    http:
      install: true
    grpc:
      install: true
```

<!-- markdownlint-disable line-length -->
| Parameter                      | Type    | Mandatory | Default value | Description                                                                                                                                                                                                                                                                                           |
| ------------------------------ | ------- | --------- | ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `http.install`                      | boolean | no        | `false`           | Install the HTTP ingress |
| `http.annotations`                  | map     | no        | `-`           | Annotations for HTTP collector Ingress                                                                                                                                                                                                                                                                     |
| `http.labels`                       | map     | no        | `-`           | Labels for HTTP collector Ingress                                                                                                                                                                                                                                                                          |
| `http.host`                         | string  | no        | `-`           | DNS name of HTTP Ingress host that should be created. If specified, ingress rules cannot be customized. Rules are auto-populated to cover all supported protocols.                                                                                                                                                                                                                                                       |
| `http.hosts`                        | array   | no        | `-`           | List of hosts                                                                                                                                                                                                                                                                                         |
| `http.hosts[].host`                 | string  | no        | `-`           | DNS name of HTTP Ingress host that should be created                                                                                                                                                                                                                                                       |
| `http.hosts[].paths`                | array   | no        | `-`           | List of paths and endpoints in HTTP Ingress                                                                                                                                                                                                                                                                |
| `http.hosts[].paths[].prefix`       | string  | no        | `-`           | Endpoint path that will listen and handle by Ingress controller (for example: `/`, `/zipkin`)                                                                                                                                                                                                         |
| `http.hosts[].paths[].service.name` | string  | no        | `-`           | Service name to which will route requests from declared in this section endpoint, by default will use `{{ .jaeger.serviceName }}-collector` (usually will be `jaeger-collector`)                                                                                                                      |
| `http.hosts[].paths[].service.port` | integer | no        | `-`           | Service port to which will route requests from declared in this section endpoint                                                                                                                                                                                                                      |
| `grpc.install`                      | boolean | no        | `false`           | Install the GRPC ingress |
| `grpc.annotations`                  | map     | no        | `-`           | Annotations for GRPC collector Ingress                                                                                                                                                                                                                                                                     |
| `grpc.labels`                       | map     | no        | `-`           | Labels for GRPC collector Ingress                                                                                                                                                                                                                                                                          |
| `grpc.host`                         | string  | no        | `-`           | DNS name of GRPC Ingress host that should be created. If specified, ingress rules cannot be customized. Rules are auto-populated to cover all supported protocols.                                                                                                                                                                                                                                                       |
| `grpc.hosts`                        | array   | no        | `-`           | List of hosts                                                                                                                                                                                                                                                                                         |
| `grpc.hosts[].host`                 | string  | no        | `-`           | DNS name of GRPC Ingress host that should be created                                                                                                                                                                                                                                                       |
| `grpc.hosts[].paths`                | array   | no        | `-`           | List of paths and endpoints in GRPC Ingress                                                                                                                                                                                                                                                                |
| `grpc.hosts[].paths[].prefix`       | string  | no        | `-`           | Endpoint path that will listen and handle by Ingress controller (for example: `/`, `/zipkin`)                                                                                                                                                                                                         |
| `grpc.hosts[].paths[].service.name` | string  | no        | `-`           | Service name to which will route requests from declared in this section endpoint, by default will use `{{ .jaeger.serviceName }}-collector` (usually will be `jaeger-collector`)                                                                                                                      |
| `grpc.hosts[].paths[].service.port` | integer | no        | `-`           | Service port to which will route requests from declared in this section endpoint                                                                                                                                                                                                                      |
<!-- markdownlint-enable line-length -->

Example:

**Note:** It's just an example of a parameter's format, not recommended parameters.

```yaml
collector:
  ingress:
    grpc:
      # Enable or disable Ingress deployment
      install: true

      annotations:
        example.annotation/key: example-annotation-value
      labels:
        example.label/key: example-label-value

      # An ability to set a single host name, like in other places
      host: jaeger-collector-grpc.test.org

      # An ability set one or more hosts with custom list of paths
      hosts:
        - host: otlp-grpc.jaeger-collector.test.org
          paths:
            - prefix: /otlp/grpc
              service:
                port: 4317
        - host: other-grpc.jaeger-collector.test.org
          paths:
            - prefix: /thrift/grpc
              service:
                port: 14267
    http:
      # Enable or disable Ingress deployment
      install: true

      annotations:
        example.annotation/key: example-annotation-value
      labels:
        example.label/key: example-label-value

      # An ability to set a single host name, like in other places
      host: jaeger-collector-http.test.org

      # An ability set one or more hosts with custom list of paths
      hosts:
        - host: otlp-http.jaeger-collector.test.org
          paths:
            - prefix: /otlp/http
              service:
                port: 4318
        - host: other-http.jaeger-collector.test.org
          paths:
            - prefix: /
              service:
                port: 16269
            - prefix: /zipkin
              service:
                port: 9411
            - prefix: /thrift/tchannel
              service:
                port: 14250
            - prefix: /thrift/http
              service:
                port: 14268
```


#### TLSConfig

This section describes TLS configuration for `jaeger-collector`.

All parameters in the table below should be specified under the key:

```yaml
collector:
  tlsConfig:
    existingSecret: ...
```

<!-- markdownlint-disable line-length -->
| Parameter                            | Type    | Mandatory | Default value                 | Description                                                                                                                                                                                                                                                                                                                                                                                                                                                |
| ------------------------------------ | ------- | --------- | ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `existingSecret`                     | string  | no        | `-`                           | Name of the pre-existing secret that contains TLS configuration for jaeger-collector. If specified, `generateCerts.enabled` must be set to `false`. The `existingSecret` is expected to contain CA certificate, TLS key and TLS certificate in `ca.crt`, `tls.key` and `tls.crt` fields respectively.                                                                                                                                                      |
| `newSecretName`                      | string  | no        | `jaeger-collector-tls-secret` | Name of the new secret that needs to be created for storing TLS configuration of jaeger-collector. Can be specified if `tlsConfig.existingSecret` is not specified.                                                                                                                                                                                                                                                                                        |
| `generateCerts.enabled`              | boolean | no        | `true`                        | Generation of certificate is enabled by default. If `tlsConfig.existingSecret` is specified, `tlsConfig.generateCerts` section will be skipped. If `tlsConfig.otelHttp.enabled` or `tlsConfig.otelgRPC.enabled` or `tlsConfig.jaegerHttp.enabled` or `tlsConfig.jaegergRPC.enabled` or `tlsConfig.zipkin.enabled` is true, `cert-manager` will generate certificate with the name configured using `tlsConfig.newSecretName`, if it doesn't exist already. |
| `generateCerts.clusterIssuerName`    | string  | no        | `-`                           | Cluster issuer name for generated certificate. If not specified, `jaeger-collector-tls-issuer` will be installed and it will generate certificates.                                                                                                                                                                                                                                                                                                        |
| `generateCerts.duration`             | integer | no        | `365`                         | Duration in days, until which issued certificate will be valid.                                                                                                                                                                                                                                                                                                                                                                                            |
| `generateCerts.renewBefore`          | integer | no        | `15`                          | Number of days before which certificate must be renewed.                                                                                                                                                                                                                                                                                                                                                                                                   |
| `createSecret`                       | object  | no        | `-`                           | New secret with the name `tlsConfig.newSecretName` will be created using already known certificate content. If `tlsConfig.existingSecret` is specified, `tlsConfig.createSecret` section will be skipped.                                                                                                                                                                                                                                                  |
| `createSecret.ca`                    | string  | no        | `-`                           | Already known CA certificate will be added to newly created secret.                                                                                                                                                                                                                                                                                                                                                                                        |
| `createSecret.key`                   | string  | no        | `-`                           | Already known TLS key will be added to newly created secret.                                                                                                                                                                                                                                                                                                                                                                                               |
| `createSecret.cert`                  | string  | no        | `-`                           | Already known TLS certificate will be added to newly created secret.                                                                                                                                                                                                                                                                                                                                                                                       |
| `otelHttp.enabled`                   | boolean | no        | `false`                       | Specifies whether TLS must be enabled for OTEL HTTP endpoint.                                                                                                                                                                                                                                                                                                                                                                                              |
| `otelHttp.cipherSuites`              | string  | no        | `-`                           | Comma-separated list of cipher suites for the server.                                                                                                                                                                                                                                                                                                                                                                                                      |
| `otelHttp.maxVersion`                | string  | no        | `-`                           | Maximum TLS version supported (Possible values: 1.0, 1.1, 1.2, 1.3).                                                                                                                                                                                                                                                                                                                                                                                       |
| `otelHttp.minVersion`                | string  | no        | `-`                           | Minimum TLS version supported (Possible values: 1.0, 1.1, 1.2, 1.3).                                                                                                                                                                                                                                                                                                                                                                                       |
| `otelHttp.certificateReloadInterval` | string  | no        | `0s`                          | The duration after which the certificate will be reloaded (0s means will not be reloaded).                                                                                                                                                                                                                                                                                                                                                                 |
| `otelgRPC.enabled`                   | boolean | no        | `false`                       | Specifies whether TLS must be enabled for OTEL GRPC endpoint.                                                                                                                                                                                                                                                                                                                                                                                              |
| `otelgRPC.cipherSuites`              | string  | no        | `-`                           | Comma-separated list of cipher suites for the server.                                                                                                                                                                                                                                                                                                                                                                                                      |
| `otelgRPC.maxVersion`                | string  | no        | `-`                           | Maximum TLS version supported (Possible values: 1.0, 1.1, 1.2, 1.3).                                                                                                                                                                                                                                                                                                                                                                                       |
| `otelgRPC.minVersion`                | string  | no        | `-`                           | Minimum TLS version supported (Possible values: 1.0, 1.1, 1.2, 1.3).                                                                                                                                                                                                                                                                                                                                                                                       |
| `otelgRPC.certificateReloadInterval` | string  | no        | `0s`                          | The duration after which the certificate will be reloaded (0s means will not be reloaded).                                                                                                                                                                                                                                                                                                                                                                 |
| `jaegerHttp.enabled`                 | boolean | no        | `false`                       | Specifies whether TLS must be enabled for Jaeger/Thrift HTTP endpoint.                                                                                                                                                                                                                                                                                                                                                                                     |
| `jaegerHttp.cipherSuites`            | string  | no        | `-`                           | Comma-separated list of cipher suites for the server.                                                                                                                                                                                                                                                                                                                                                                                                      |
| `jaegerHttp.maxVersion`              | string  | no        | `-`                           | Maximum TLS version supported (Possible values: 1.0, 1.1, 1.2, 1.3).                                                                                                                                                                                                                                                                                                                                                                                       |
| `jaegerHttp.minVersion`              | string  | no        | `-`                           | Minimum TLS version supported (Possible values: 1.0, 1.1, 1.2, 1.3).                                                                                                                                                                                                                                                                                                                                                                                       |
| `jaegergRPC.enabled`                 | boolean | no        | `false`                       | Specifies whether TLS must be enabled for Jaeger/Thrift GRPC endpoint.                                                                                                                                                                                                                                                                                                                                                                                     |
| `jaegergRPC.cipherSuites`            | string  | no        | `-`                           | Comma-separated list of cipher suites for the server.                                                                                                                                                                                                                                                                                                                                                                                                      |
| `jaegergRPC.maxVersion`              | string  | no        | `-`                           | Maximum TLS version supported (Possible values: 1.0, 1.1, 1.2, 1.3).                                                                                                                                                                                                                                                                                                                                                                                       |
| `jaegergRPC.minVersion`              | string  | no        | `-`                           | Minimum TLS version supported (Possible values: 1.0, 1.1, 1.2, 1.3).                                                                                                                                                                                                                                                                                                                                                                                       |
| `zipkin.enabled`                     | boolean | no        | `false`                       | Specifies whether TLS must be enabled for Zipkin endpoint.                                                                                                                                                                                                                                                                                                                                                                                                 |
| `zipkin.cipherSuites`                | string  | no        | `-`                           | Comma-separated list of cipher suites for the server.                                                                                                                                                                                                                                                                                                                                                                                                      |
| `zipkin.maxVersion`                  | string  | no        | `-`                           | Maximum TLS version supported (Possible values: 1.0, 1.1, 1.2, 1.3).                                                                                                                                                                                                                                                                                                                                                                                       |
| `zipkin.minVersion`                  | string  | no        | `-`                           | Minimum TLS version supported (Possible values: 1.0, 1.1, 1.2, 1.3).                                                                                                                                                                                                                                                                                                                                                                                       |
<!-- markdownlint-enable line-length -->

Example:

**Note:** It's just an example of a parameter's format, not recommended parameters.

```yaml
collector:
  tlsConfig:
    #existingSecret: jaeger-collector-tls-secret
    newSecretName: jaeger-collector-tls-secret
    generateCerts:
      enabled: true
      clusterIssuerName: ""
      duration: 365
      renewBefore: 15
    #createSecret:
    #  ca: |-
    #    -----BEGIN CERTIFICATE-----
    #    ... certificate content ...
    #    -----END CERTIFICATE-----
    #  key: |-
    #    -----BEGIN RSA PRIVATE KEY-----
    #    ... certificate content ...
    #    -----END RSA PRIVATE KEY-----
    #  cert: |-
    #    -----BEGIN CERTIFICATE-----
    #    ... certificate content ...
    #    -----END CERTIFICATE-----
    otelHttp:
      enabled: true
      cipherSuites: TLS_RSA_WITH_RC4_128_SHA,TLS_RSA_WITH_3DES_EDE_CBC_SHA,TLS_RSA_WITH_AES_128_CBC_SHA
      maxVersion: 1.2
      minVersion: 1.2
      certificateReloadInterval: 0s
    otelgRPC:
      enabled: true
      maxVersion: 1.2
      minVersion: 1.2
      certificateReloadInterval: 0s
    jaegergRPC:
      enabled: true
      maxVersion: 1.2
      minVersion: 1.2
    jaegerHttp:
      enabled: true
      maxVersion: 1.2
      minVersion: 1.2
    zipkin:
      enabled: true
      maxVersion: 1.2
      minVersion: 1.2
```


### Query

`jaeger-query` is a service that exposes the APIs for retrieving traces from storage and hosts a Web UI for searching
and analyzing traces.

All parameters in the table below should be specified under the key:

```yaml
query:
  install: true
  ...
```

<!-- markdownlint-disable line-length -->
| Parameter                  | Type                                                                                                                          | Mandatory | Default value                                                              | Description                                                                                                                         |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | --------- | -------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `install`                  | boolean                                                                                                                       | no        | true                                                                       | Allows enabling/disabling creating query deployment                                                                                 |
| `image`                    | string                                                                                                                        | no        | -                                                                          | Docker image to use for a query container                                                                                           |
| `imagePullPolicy`          | string                                                                                                                        | no        | IfNotPresent                                                               | `imagePullPolicy` for a container and the tag of the image affects when the kubelet attempts to pull (download) the specified image |
| `imagePullSecrets`         | object                                                                                                                        | no        | []                                                                         | Keys to access the private registry                                                                                                 |
| `cmdlineParams`            | object                                                                                                                        | no        | []                                                                         | Query-related cmd line opts to be configured on the concerned components                                                            |
| `extraEnv`                 | object                                                                                                                        | no        | []                                                                         | Query-related extra env vars to be configured on the concerned components                                                           |
| `config`                   | boolean                                                                                                                       | no        | false                                                                      | Enabling/disabling creating query UI config                                                                                         |
| `ingress.install`          | boolean                                                                                                                       | no        | false                                                                      | Enabling/disabling creating query ingress                                                                                           |
| `ingress.host`             | string                                                                                                                        | no        | -                                                                          | FQDN of the ingress host                                                                                                            |
| `route.install`            | boolean                                                                                                                       | no        | false                                                                      | Enabling/disabling creating query route                                                                                             |
| `route.host`               | string                                                                                                                        | no        | -                                                                          | FQDN of the route host                                                                                                              |
| `resources`                | object                                                                                                                        | no        | {requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: 200m, memory: 256Mi}} | Describes computing resource requests and limits for single Pods                                                                    |
| `securityContext`          | [core/v1.PodSecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#podsecuritycontext-v1-core) | no        | {}                                                                         | Describes pod-level security attributes                                                                                             |
| `containerSecurityContext` | [core/v1.SecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#securitycontext-v1-core)       | no        | {}                                                                         | Holds container-level security attributes                                                                                           |
| `priorityClassName`        | string                                                                                                                        | no        | `-`                                                                        | PriorityClassName assigned to the Pods to prevent them from evicting                                                                |
| `labels`                   | map                                                                                                                           | no        | {}                                                                         | Labels for query                                                                                                                    |
| `annotations`              | map                                                                                                                           | no        | {}                                                                         | Annotations for query                                                                                                               |
<!-- markdownlint-enable line-length -->

**Note:** It's just an example of a parameter's format, not recommended parameters.

Example of all parameters:

```yaml
query:
  install: true
  replicas: 1

  image: jaegertracing/jaeger-query:1.62.0
  imagePullPolicy: IfNotPresent
  imagePullSecrets:
  - name: jaeger-pull-secret

  cmdlineParams:
    - '--cassandra.max-retry-attempts=10'
  extraEnv:
    - name: CASSANDRA_TIMEOUT
      value: 30s

  # Enable mounting Jaeger UI config
  config: true

  # Use in Kubernetes
  ingress:
    install: true
    host: query.cloud.test.org
  # Use in OpenShift
  route:
    install: false
    host: query.cloud.test.org

  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 200m
      memory: 256Mi
  securityContext:
    runAsUser: 2000
    fsGroup: 2000
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containerSecurityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
  priorityClassName: priority-class
  annotations:
    example.annotation/key: example-annotation-value
  labels:
    example.label/key: example-label-value
```


### Readiness probe

`readiness-probe` is a sidecar container in the collector and query services that checks health of volume.

All parameters in the table below should be specified under the key:

```yaml
readinessProbe:
  ...
```

<!-- markdownlint-disable line-length -->
| Parameter         | Type   | Mandatory | Default value                                                              | Description                                                                                                                                                   |
| ----------------- | ------ | --------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `image`           | string | no        | -                                                                          | Docker image to use for a readiness-probe container                                                                                                           |
| `imagePullPolicy` | string | no        | IfNotPresent                                                               | `imagePullPolicy` for a container and the tag of the image affects when the kubelet attempts to pull (download) the specified image                           |
| `args`            | object | yes       | []                                                                         | Cmd line opts to be configured. More [here](readiness-probe.md) |
| `resources`       | object | no        | {requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: 200m, memory: 256Mi}} | Describes computing resource requests and limits for single Pods                                                                                              |
<!-- markdownlint-enable line-length -->

**Note:** It's just an example of a parameter's format, not recommended parameters.

Example of all parameters:

```yaml
readinessProbe:
  image: "ghcr.io/netcracker/jaeger-readiness-probe:main"
  imagePullPolicy: IfNotPresent
  args:
    - "-namespace=tracing"
    - "-host=cassandra.cassandra.svc"
    - "-port=9042"
    - "-storage=cassandra"
    - "-datacenter=datacenter1"
    - "-keyspace=jaeger"
    - "-testtable=service_names"
    - "-authSecretName=jaeger-cassandra-auth-secret"
    - "-tlsEnabled=true"
    - "-certsSecretName=jaeger-cassandra-tls-secret"
    - "-errors=5"
    - "-retries=5"
    - "-timeout=5"
    - "-shutdownTimeout=5"
    - "-servicePort=8080"
  resources:
    requests:
      cpu: 50m
      memory: 50Mi
    limits:
      cpu: 50m
      memory: 50Mi
```


### Cassandra

**Note:** Since Jaeger release `1.57.x`, `cassandraSchemaJob.install` parameter has been removed.
`cassandraSchemaJob` will be installed if `jaeger.storage.type` is set to `cassandra`.

**Warning!** TTL for Jaeger's Cassandra tables **can't be changed** during update!
You must set correct TTL values during first deploy! If you didn't do it, please read the
[Maintenance: Change Cassandra TTL](maintenance.md#change-cassandra-ttl).

```yaml
cassandraSchemaJob:
  name: cassandra-schema-job
  ...
```

<!-- markdownlint-disable no-inline-html -->
<!-- markdownlint-disable line-length -->
| Parameter                  | Type                                                                                                                          | Mandatory | Default value                                                                                                                             | Description                                                                                                                                                                                                                                                                                                                                           |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | --------- | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `image`                    | string                                                                                                                        | no        | -                                                                                                                                         | The docker image to use for a `cassandraSchemaJob` container                                                                                                                                                                                                                                                                                          |
| `name`                     | string                                                                                                                        | no        | cassandra-schema-job                                                                                                                      | The name of a microservice to deploy with                                                                                                                                                                                                                                                                                                             |
| `imagePullPolicy`          | string                                                                                                                        | no        | IfNotPresent                                                                                                                              | `imagePullPolicy` for a container and the tag of the image affects when the `kubelet` attempts to pull (download) the specified image                                                                                                                                                                                                                 |
| `imagePullSecrets`         | object                                                                                                                        | no        | []                                                                                                                                        | Keys to access the private registry                                                                                                                                                                                                                                                                                                                   |
| `host`                     | string                                                                                                                        | no        | -                                                                                                                                         | The host used to connect to Cassandra                                                                                                                                                                                                                                                                                                                 |
| `port`                     | string                                                                                                                        | no        | 9042                                                                                                                                      | The port used to connect to Cassandra                                                                                                                                                                                                                                                                                                                 |
| `username`                 | string                                                                                                                        | no        | -                                                                                                                                         | A username for Cassandra with access to HTTP API                                                                                                                                                                                                                                                                                                      |
| `password`                 | string                                                                                                                        | no        | -                                                                                                                                         | A password for Cassandra with access to HTTP API                                                                                                                                                                                                                                                                                                      |
| `mode`                     | string                                                                                                                        | no        | test                                                                                                                                      | The Cassandra mode, and available values - `prod` or `test`                                                                                                                                                                                                                                                                                           |
| `datacenter`               | string                                                                                                                        | no        | -                                                                                                                                         | The Cassandra datacenter                                                                                                                                                                                                                                                                                                                              |
| `keyspace`                 | string                                                                                                                        | no        | jaeger                                                                                                                                    | The Cassandra keyspace for Jaeger                                                                                                                                                                                                                                                                                                                     |
| `allowedAuthenticators`    | array                                                                                                                         | no        | All values from gocql driver                                                                                                              | List of allowed authenticators for gocql driver. Full list of supported authenticators cna be found in the gocql source code [https://github.com/apache/cassandra-gocql-driver/blob/34fdeebefcbf183ed7f916f931aa0586fdaa1b40/conn.go#L27](https://github.com/apache/cassandra-gocql-driver/blob/34fdeebefcbf183ed7f916f931aa0586fdaa1b40/conn.go#L27) |
| `existingSecret`           | object                                                                                                                        | no        | -                                                                                                                                         | The name of the existing secret with Cassandra username and password                                                                                                                                                                                                                                                                                  |
| `extraEnv`                 | object                                                                                                                        | no        | []                                                                                                                                        | The Cassandra schema job-related extra env vars to be configured on the concerned components                                                                                                                                                                                                                                                          |
| `labels`                   | map                                                                                                                           | no        | {}                                                                                                                                        | Map of string keys and values that can be used to organize and categorize (scope and select) objects                                                                                                                                                                                                                                                  |
| `resources`                | object                                                                                                                        | no        | {}                                                                                                                                        | Computing resource requests and limits for single Pods                                                                                                                                                                                                                                                                                                |
| `securityContext`          | [core/v1.PodSecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#podsecuritycontext-v1-core) | no        | {}                                                                                                                                        | Holds pod-level security attributes                                                                                                                                                                                                                                                                                                                   |
| `containerSecurityContext` | [core/v1.SecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#securitycontext-v1-core)       | no        | {}                                                                                                                                        | Holds container-level security attributes                                                                                                                                                                                                                                                                                                             |
| `tls.enabled`              | boolean                                                                                                                       | no        | false                                                                                                                                     | Enabling or disabling TLS connection to Cassandra                                                                                                                                                                                                                                                                                                     |
| `tls.existingSecret`       | string                                                                                                                        | no        | -                                                                                                                                         | The name of the existing secret with SSL certificates. If specified, all subsequent parameters in tls section are ignored.                                                                                                                                                                                                                            |
| `tls.commonName`           | string                                                                                                                        | no        | -                                                                                                                                         | The common name - server name protected by the SSL certificate. Ignored if the `existingSecret` is specified.                                                                                                                                                                                                                                         |
| `tls.ca`                   | string                                                                                                                        | no        | -                                                                                                                                         | CA certificate. It use to provide a list of trusted CA who issued the certificates. The mandatory field when using an SSL connection to Cassandra. Ignored if the `existingSecret`is specified.                                                                                                                                                       |
| `tls.key`                  | string                                                                                                                        | no        | -                                                                                                                                         | The public key of the certificate. The mandatory field when using an SSL connection to Cassandra. Ignored if the `existingSecret` is specified.                                                                                                                                                                                                       |
| `tls.cert`                 | string                                                                                                                        | no        | -                                                                                                                                         | The private part of the certificate. The mandatory field when using an SSL connection to Cassandra. Ignored if the `existingSecret` is specified.                                                                                                                                                                                                     |
| `tls.cqlshrc`              | string                                                                                                                        | no        | [ssl]<br/>certfile = /cassandra-tls/ca-cert.pem<br/>usercert = /cassandra-tls/client-cert.pem<br/>userkey = /cassandra-tls/client-key.pem | An overriding path to certificates which will use `cqlsh` to connect to Cassandra. Ignored if the `existingSecret` is specified                                                                                                                                                                                                                       |
| `ttl.trace`                | integer                                                                                                                       | no        | -                                                                                                                                         | Time to live for traces (in seconds) data                                                                                                                                                                                                                                                                                                             |
| `ttl.dependencies`         | integer                                                                                                                       | no        | -                                                                                                                                         | Time to live for dependencies (in seconds)data                                                                                                                                                                                                                                                                                                        |
| `priorityClassName`        | string                                                                                                                        | no        | `-`                                                                                                                                       | PriorityClassName assigned to the Pods to prevent them from evicting.                                                                                                                                                                                                                                                                                 |
| `labels`                   | map                                                                                                                           | no        | {}                                                                                                                                        | Labels for cassandra schema job.                                                                                                                                                                |
| `annotations`              | map                                                                                                                           | no        | {}                                                                                                                                        | Annotations for cassandra schema job.                                                                                                                                                           |
<!-- markdownlint-enable line-length -->
<!-- markdownlint-enable no-inline-html -->

Examples:

**Note:** It's just an example of a parameter's format, not recommended parameters.

```yaml
cassandraSchemaJob:
  name: cassandra-schema-job

  image: jaegertracing/jaeger-cassandra-schema:1.62.0
  imagePullPolicy: IfNotPresent
  imagePullSecrets:
    - name: jaeger-pull-secret

  labels:
    example.label/key: example-label-value

  host: cassandra.cassandra.svc
  port: 9043
  username: admin
  password: admin
  mode: prod
  keyspace: jaeger
  datacenter: dc1

  allowedAuthenticators:
    - org.apache.cassandra.auth.PasswordAuthenticator
    - com.instaclustr.cassandra.auth.SharedSecretAuthenticator
    - com.datastax.bdp.cassandra.auth.DseAuthenticator

  tls:
    enabled: true
    commonName: cassandra-server

    # Mutually exclusive with "ca", "cert", "key" parameters
    existingSecret: cassandra-certificate-secret

    # Mutually exclusive with "existingSecret" parameter
    ca: |-
      -----BEGIN CERTIFICATE-----
      <content>
      -----END CERTIFICATE-----
    cert: |-
      -----BEGIN CERTIFICATE-----
      <content>
      -----END CERTIFICATE-----
    key: |-
      -----EGIN RSA PRIVATE KEY-----
      <content>
      -----END RSA PRIVATE KEY-----
    cqlshrc: |-
      [ssl]
      certfile = /cassandra-tls/ca-cert.pem
      usercert = /cassandra-tls/client-cert.pem
      userkey = /cassandra-tls/client-key.pem

  ttl:
    trace: 172800    # in seconds
    dependencies: 0  # in seconds

  existingSecret:
  extraEnv:
    - name: CASSANDRA_TIMEOUT
      value: 30s
  
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
    limits:
      cpu: 100m
      memory: 128Mi
  securityContext:
    runAsUser: 2000
    fsGroup: 2000
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containerSecurityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
  priorityClassName: priority-class
  annotations:
    example.annotation/key: example-annotation-value
  labels:
    example.label/key: example-label-value
```


### ElasticSearch

All parameters in the table below should be specified under the key:

```yaml
elasticsearch:
  ...
```

<!-- markdownlint-disable line-length -->
| Parameter                       | Type    | Mandatory | Default value | Description                                                                                                                                                                                     |
| ------------------------------- | ------- | --------- | ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `existingSecret`                | string  | no        | -             | Name of the existing secret with ElasticSearch username and password                                                                                                                            |
| `indexPrefix`                   | string  | no        | -             | Index prefix for ElasticSearch                                                                                                                                                                  |
| `extraEnv`                      | object  | no        | []            | Elasticsearch-related extra env vars to be configured on the concerned components                                                                                                               |
| `client.url`                    | string  | no        | -             | The URL with the port used to connect to Elasticsearch                                                                                                                                          |
| `client.username`               | string  | no        | -             | Username for Elasticsearch with access to HTTP API                                                                                                                                              |
| `client.password`               | string  | no        | -             | Password for Elasticsearch with access to HTTP API                                                                                                                                              |
| `client.scheme`                 | string  | no        | http          | The scheme for Elasticsearch with access to HTTP API                                                                                                                                            |
| `client.tls.enabled`            | false   | no        | -             | Enabling or disabling TLS connection to OpenSearch/ElasticSearch.                                                                                                                               |
| `client.tls.existingSecret`     | string  | no        | -             | The name of the existing secret with SSL certificates. If specified, all subsequent parameters in tls section are ignored.                                                                      |
| `client.tls.commonName`         | string  | on        | -             | The common name - server name protected by the SSL certificate. Ignored if the `existingSecret` is specified.                                                                                   |
| `client.tls.ca`                 | string  | no        | -             | CA certificate. It use to provide a list of trusted CA who issued the certificates. The mandatory field when using an SSL connection to Cassandra. Ignored if the `existingSecret`is specified. |
| `client.ts.cert`                | string  | no        | -             | The private part of the certificate. The mandatory field when using an SSL connection to Cassandra. Ignored if the `existingSecret` is specified.                                               |
| `client.tls.key`                | string  | no        | -             | Specifying the public key of the certificate. The mandatory field when using an SSL connection to Cassandra. Ignored if the `existingSecret` is specified.                                      |
| `client.tls.insecureSkipVerify` | boolean | no        | -             | Disabling certificate validation check for OpenSearch/ElasticSearch TLS connection                                                                                                              |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not recommended parameters.

```yaml
elasticsearch:
  existingSecret: 
  indexPrefix: custom-  # result name of indexes will be custom-jaeger-spans, custom-jaeger-.....
  extraEnv:
  - name: ES_TIMEOUT
    value: 30s

  client:
    url: opensearch.opensearch.svc
    username: <username>
    password: <password>
    scheme: https

    # only in case when schema https
    tls:
      enabled: true
      commonName: opensearch-service

      # Mutually exclusive with "ca", "cert", "key" parameters
      existingSecret: es-certificates-secret

      # Mutually exclusive with "existingSecret" parameter
      ca: |-
        -----BEGIN CERTIFICATE-----
        <content>
        -----END CERTIFICATE-----
      cert: |-
        -----BEGIN CERTIFICATE-----
        <content>
        -----END CERTIFICATE-----
      key: |-
        -----BEGIN PRIVATE KEY-----
        <content>
        -----END PRIVATE KEY-----

      # Insecure and strongly doesn't recommended for production
      insecureSkipVerify: true
```


#### Index Cleaner

All parameters in the table below should be specified under the key:

```yaml
elasticsearch:
  indexCleaner:
    ...
```

<!-- markdownlint-disable line-length -->
| Parameter                    | Type                                                                                                                          | Mandatory | Default value                                                              | Description                                                                                                                             |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | --------- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `install`                    | boolean                                                                                                                       | no        | false                                                                      | Enabling or disabling creating indexCleaner CronJob                                                                                     |
| `image`                      | string                                                                                                                        | no        | -                                                                          | The docker image to use for an `indexCleaner` container                                                                                 |
| `name`                       | string                                                                                                                        | no        | index-cleaner                                                              | The name of a microservice to deploy with                                                                                               |
| `imagePullPolicy`            | string                                                                                                                        | no        | IfNotPresent                                                               | The `imagePullPolicy` for a container and the tag of the image affects when the kubelet attempts to pull (download) the specified image |
| `imagePullSecrets`           | object                                                                                                                        | no        | []                                                                         | Keys to access the private registry                                                                                                     |
| `concurrencyPolicy`          | string                                                                                                                        | no        | Forbid                                                                     | Specifies how to treat concurrent executions of a job that is created by this cron job                                                  |
| `labels`                     | map                                                                                                                           | no        | {}                                                                         | Map of string keys and values that can be used to organize and categorize (scope and select) objects                                    |
| `annotations`                | map                                                                                                                           | no        | {}                                                                         | An unstructured key-value map stored with a resource that may be set by external tools to store and retrieve arbitrary metadata         |
| `schedule`                   | string                                                                                                                        | no        | `55 23 * * *`                                                              | The scheduled time of its jobs to be created and executed                                                                               |
| `successfulJobsHistoryLimit` | integer                                                                                                                       | no        | 1                                                                          | How many completed jobs should be kept                                                                                                  |
| `failedJobsHistoryLimit`     | integer                                                                                                                       | no        | 1                                                                          | How many failed jobs should be kept                                                                                                     |
| `ttlSecondsAfterFinished`    | integer                                                                                                                       | no        | 0                                                                          | How many seconds after finished job's pod will be available                                                                             |
| `numberOfDays`               | integer                                                                                                                       | no        | 7                                                                          | The number of days that the job will be executed                                                                                        |
| `extraEnv`                   | object                                                                                                                        | no        | []                                                                         | An `indexCleaner` related extra env vars to be configured on the concerned components                                                   |
| `extraConfigmapMounts`       | object                                                                                                                        | no        | []                                                                         | Extra configMap mounts for indexCleaner                                                                                                 |
| `extraSecretMounts`          | object                                                                                                                        | no        | []                                                                         | Extra secret mounts for indexCleaner                                                                                                    |
| `nodeSelector`               | map                                                                                                                           | no        | {}                                                                         | Defining which Nodes the Pods are scheduled on                                                                                          |
| `tolerations`                | [core/v1.Toleration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core)                 | no        | {}                                                                         | The pods to schedule onto nodes with matching taints                                                                                    |
| `resources`                  | object                                                                                                                        | no        | {requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: 100m, memory: 128Mi}} | Computing resource requests and limits for single Pods                                                                                  |
| `securityContext`            | [core/v1.PodSecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#podsecuritycontext-v1-core) | no        | {}                                                                         | Holds pod-level security attributes                                                                                                     |
| `containerSecurityContext`   | [core/v1.SecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#securitycontext-v1-core)       | no        | {}                                                                         | Holds container-level security attributes                                                                                               |
| `priorityClassName`          | string                                                                                                                        | no        | `-`                                                                        | PriorityClassName assigned to the Pods to prevent them from evicting.                                                                   |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not recommended parameters.

```yaml
elasticsearch:
  indexCleaner:
    install: true
    name: index-cleaner

    image: jaegertracing/jaeger-es-index-cleaner:1.62.0
    imagePullPolicy: IfNotPresent
    imagePullSecrets:
      - name: jaeger-pull-secret

    labels:
      example.label/key: example-label-value
    annotations:
      example.annotation/key: example-annotation-value

    numberOfDays: 7

    schedule: 55 23 * * *
    concurrencyPolicy: Forbid
    successfulJobsHistoryLimit: 1
    failedJobsHistoryLimit: 1
    ttlSecondsAfterFinished: 0

    extraEnv:
      - name: ES_TIMEOUT
        value: 30s
    extraConfigmapMounts:
      - name: extra-config-file-name  # name of mount in pod
        configMap: extra-configmap-name  # name of ConfigMap in the Kubernetes
    extraSecretMounts:
      - name: extra-config-file-name  # name of mount in pod
        secretMap: extra-secret-name  # name of Secret in the Kubernetes

    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 100m
        memory: 128Mi
    securityContext:
      runAsUser: 2000
      fsGroup: 2000
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
    containerSecurityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL

    nodeSelector:
      node-role.kubernetes.io/worker: worker
    tolerations:
    - key: key1
      operator: Equal
      value: value1
      effect: NoSchedule
    priorityClassName: priority-class
```


#### Rollover

Elasticsearch Rollover is an index management strategy that optimizes use of resources allocated to indices.
For example, indices that do not contain any data still allocate shards, and conversely, a single index might contain
significantly more data than the others.
Jaeger by default stores data in daily indices which might not optimally utilize resources.

One additional part of Elasticsearch Rollover is [Lookback job](#lookback).

More details about Elasticsearch Rollover can be found by the link
[https://www.jaegertracing.io/docs/latest/deployment/#elasticsearch-rollover](https://www.jaegertracing.io/docs/latest/deployment/#elasticsearch-rollover)

**Warning!** Do not use Rollover (rollover and lookback) and IndexCleaner together. Need to use only one cleanup strategy!

All parameters in the table below should be specified under the key:

```yaml
elasticsearch:
  rollover:
    install: true
    ...
```

<!-- markdownlint-disable line-length -->
| Parameter                          | Type                                                                                                                          | Mandatory | Default value | Description                                                                                                                             |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | --------- | ------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `install`                          | boolean                                                                                                                       | no        | false         | Enabling or disabling creating rollover CronJob                                                                                         |
| `image`                            | string                                                                                                                        | no        | -             | Docker image to use for a rollover container                                                                                            |
| `name`                             | string                                                                                                                        | no        | rollover      | The name of a microservice to deploy with                                                                                               |
| `imagePullPolicy`                  | string                                                                                                                        | no        | IfNotPresent  | `imagePullPolicy` for a container and the tag of the image affects when the kubelet attempts to pull (download) the specified image     |
| `imagePullSecrets`                 | list[map]                                                                                                                     | no        | -             | List of secret names to access the private registry                                                                                     |
| `concurrencyPolicy`                | string                                                                                                                        | no        | Forbid        | How to treat concurrent executions of a job that is created by this cron job                                                            |
| `labels`                           | map[string]string                                                                                                             | no        | {}            | Map of string keys and values that can be used to organize and categorize (scope and select) objects                                    |
| `annotations`                      | map[string]string                                                                                                             | no        | {}            | Map are an unstructured key-value map stored with a resource that may be set by external tools to store and retrieve arbitrary metadata |
| `schedule`                         | string                                                                                                                        | no        | `10 0 * *`    | Scheduled time of its jobs to be created and executed (in the [cron](https://en.wikipedia.org/wiki/Cron) format)                        |
| `successfulJobsHistoryLimit`       | integer                                                                                                                       | no        | 1             | How many completed jobs should be kept                                                                                                  |
| `failedJobsHistoryLimit`           | integer                                                                                                                       | no        | 1             | How many failed jobs should be kept                                                                                                     |
| `ttlSecondsAfterFinished`          | integer                                                                                                                       | no        | 0             | How many seconds after finished job's pod will be available                                                                             |
| `nodeSelector`                     | map                                                                                                                           | no        | {}            | Defining which Nodes the Pods are scheduled on                                                                                          |
| `tolerations`                      | [core/v1.Toleration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core)                 | no        | {}            | Allows the pods to schedule onto nodes with matching taints                                                                             |
| `extraEnv`                         | object                                                                                                                        | no        | []            | Rollover-related extra env vars to be configured on the concerned components                                                            |
| `extraConfigmapMounts`             | object                                                                                                                        | no        | []            | Extra configMap mounts for rollover                                                                                                     |
| `extraSecretMounts`                | object                                                                                                                        | no        | []            | Extra secret mounts for rollover                                                                                                        |
| `resources`                        | object                                                                                                                        | no        | {}            | Describes computing resource requests and limits for single Pods                                                                        |
| `securityContext`                  | [core/v1.PodSecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#podsecuritycontext-v1-core) | no        | {}            | Describes pod-level security attributes                                                                                                 |
| `containerSecurityContext`         | [core/v1.SecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#securitycontext-v1-core)       | no        | {}            | Holds container-level security attributes                                                                                               |
| `initHook.name`                    | string                                                                                                                        | no        | rollover-init | The name of a microservice to deploy with                                                                                               |
| `initHook.ttlSecondsAfterFinished` | integer                                                                                                                       | no        | 120           | TTL in seconds after the finished initial job                                                                                           |
| `initHook.extraEnv`                | object                                                                                                                        | no        | []            | Rollover-init related extra env vars to be configured on the concerned components                                                       |
| `priorityClassName`                | string                                                                                                                        | no        | `-`           | PriorityClassName assigned to the Pods to prevent them from evicting.                                                                   |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not recommended parameters.

```yaml
elasticsearch:
  rollover:
    install: true
    name: rollover
    image: jaegertracing/jaeger-es-rollover:1.62.0

    init:
      name: rollover-init
      ttlSecondsAfterFinished: 120
      extraEnv:
        - name: ES_TIMEOUT
          value: 30s

    labels:
      example.label/key: example-label-value
    annotations:
      example.annotation/key: example-annotation-value

    imagePullPolicy: IfNotPresent
    imagePullSecrets:
      - name: jaeger-pull-secret

    schedule: 10 0 * *
    concurrencyPolicy: Forbid
    successfulJobsHistoryLimit: 1
    failedJobsHistoryLimit: 1

    extraEnv:
      - name: ES_TIMEOUT
        value: 30s
    extraConfigmapMounts:
      - name: extra-config-file-name  # name of mount in pod
        configMap: extra-configmap-name  # name of ConfigMap in the Kubernetes
    extraSecretMounts:
      - name: extra-config-file-name  # name of mount in pod
        secretMap: extra-secret-name  # name of Secret in the Kubernetes

    resources:
      requests:
        cpu: 100m
        memory: 256Mi
      limits:
        cpu: 500m
        memory: 512Mi
    securityContext:
      runAsUser: 2000
      fsGroup: 2000
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
    containerSecurityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL

    nodeSelector:
      node-role.kubernetes.io/worker: worker
    tolerations:
      - key: key1
        operator: Equal
        value: value1
        effect: NoSchedule
    priorityClassName: priority-class
```


#### Lookback

It's a part of [ElasticSearch Rollover](#rollover) to remove old indices from read aliases.
It means that old data will not be available for search.
This imitates the behavior of `--es.max-span-age` flag used in the default index-per-day deployment.
This step could be optional and old indices could be simply removed by index cleaner in the next step.

**Warning!** Do not use Rollover (rollover and lookback) and IndexCleaner together. Need to use only one cleanup strategy!

All parameters in the table below should be specified under the key:

```yaml
elasticsearch:
  lookback:
    install: true
    ...
```

<!-- markdownlint-disable line-length -->
| Parameter                    | Type                                                                                                                          | Mandatory | Default value                                                              | Description                                                                                                                             |
| ---------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | --------- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `install`                    | boolean                                                                                                                       | no        | false                                                                      | Enabling or disabling creating lookback CronJob                                                                                         |
| `name`                       | string                                                                                                                        | no        | lookback                                                                   | The name of a microservice to deploy with                                                                                               |
| `imagePullPolicy`            | string                                                                                                                        | no        | IfNotPresent                                                               | The `imagePullPolicy` for a container and the tag of the image affects when the kubelet attempts to pull (download) the specified image |
| `imagePullSecrets`           | object                                                                                                                        | no        | -                                                                          | Keys to access the private registry                                                                                                     |
| `concurrencyPolicy`          | object                                                                                                                        | no        | Forbid                                                                     | Specifies how to treat concurrent executions of a job that is created by this cron job                                                  |
| `labels`                     | map                                                                                                                           | no        | {}                                                                         | Map of string keys and values that can be used to organize and categorize (scope and select) objects                                    |
| `annotations`                | map                                                                                                                           | no        | {}                                                                         | An unstructured key-value map stored with a resource that may be set by external tools to store and retrieve arbitrary metadata         |
| `schedule`                   | string                                                                                                                        | no        | `5 0 * * *`                                                                | The scheduled time of its jobs to be created and executed                                                                               |
| `successfulJobsHistoryLimit` | integer                                                                                                                       | no        | 1                                                                          | How many completed jobs should be kept                                                                                                  |
| `failedJobsHistoryLimit`     | integer                                                                                                                       | no        | 1                                                                          | How many failed jobs should be kept                                                                                                     |
| `ttlSecondsAfterFinished`    | integer                                                                                                                       | no        | 0                                                                          | How many seconds after finished job's pod will be available                                                                             |
| `nodeSelector`               | map                                                                                                                           | no        | {}                                                                         | Defining which Nodes the Pods are scheduled on                                                                                          |
| `tolerations`                | [core/v1.Toleration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core)                 | no        | {}                                                                         | The pods to schedule onto nodes with matching taints                                                                                    |
| `extraEnv`                   | object                                                                                                                        | no        | []                                                                         | Extra env vars to be configured on the concerned components                                                                             |
| `extraConfigmapMounts`       | object                                                                                                                        | no        | []                                                                         | Extra configMap mounts for lookback                                                                                                     |
| `extraSecretMounts`          | object                                                                                                                        | no        | {}                                                                         | Extra secret mounts for lookback                                                                                                        |
| `resources`                  | object                                                                                                                        | no        | {requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: 100m, memory: 128Mi}} | Computing resource requests and limits for single Pods                                                                                  |
| `securityContext`            | [core/v1.PodSecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#podsecuritycontext-v1-core) | no        | {}                                                                         | Holds pod-level security attributes                                                                                                     |
| `containerSecurityContext`   | [core/v1.SecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#securitycontext-v1-core)       | no        | {}                                                                         | Holds container-level security attributes                                                                                               |
| `priorityClassName`          | string                                                                                                                        | no        | `-`                                                                        | PriorityClassName assigned to the Pods to prevent them from evicting.                                                                   |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not recommended parameters.

```yaml
elasticsearch:
  lookback:
    install: true
    name: lookback

    image: jaegertracing/jaeger-es-rollover:1.62.0
    imagePullPolicy: IfNotPresent
    imagePullSecrets:
      - name: jaeger-pull-secret

    labels:
      example.label/key: example-label-value
    annotations:
      example.annotation/key: example-annotation-value

    schedule: 5 0 * * *
    concurrencyPolicy: Forbid
    successfulJobsHistoryLimit: 1
    failedJobsHistoryLimit: 1
    ttlSecondsAfterFinished: 0

    extraEnv:
      - name: ES_TIMEOUT
        value: 30s
    extraConfigmapMounts:
      - name: extra-config-file-name  # name of mount in pod
        configMap: extra-configmap-name  # name of ConfigMap in the Kubernetes
    extraSecretMounts:
      - name: extra-config-file-name  # name of mount in pod
        secretMap: extra-secret-name  # name of Secret in the Kubernetes

    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 100m
        memory: 128Mi
    securityContext:
      runAsUser: 2000
      fsGroup: 2000
      runAsNonRoot: true
      seccompProfile:
        type: RuntimeDefault
    containerSecurityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
          - ALL

    nodeSelector:
      node-role.kubernetes.io/worker: worker
    tolerations:
      - key: key1
        operator: Equal
        value: value1
        effect: NoSchedule
    priorityClassName: priority-class
```


### Proxy

All parameters in the table below should be specified under the key:

```yaml
proxy:
  install: true
  ...
```

<!-- markdownlint-disable line-length -->
| Parameter                      | Type                                                                                                                          | Mandatory | Default value                                                             | Description                                                                                                       |
| ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- | --------- | ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `install`                      | boolean                                                                                                                       | no        | false                                                                     | Allows enabling/disabling creating the proxy container                                                            |
| `image`                        | string                                                                                                                        | no        | -                                                                         | Docker image to use for the proxy container                                                                       |
| `access_logs_enabled`                        | boolean                                                                                                                        | no        | `true`                                                                         | Enable/Disable access logs.                                                                       |
| `type`                         | string                                                                                                                        | no        | basic                                                                     | Authentication type to be used. Available values - `basic` and `oauth2`                                           |
| `basic.users`                  | map                                                                                                                           | no        | []                                                                        | List of `login:password` in base64                                                                                |
| `oauth2.tokenEndpoint`         | string                                                                                                                        | no        | -                                                                         | Endpoint on the authorization server to retrieve the access token. Must contain scheme (`http` or `https`)        |
| `oauth2.authorizationEndpoint` | string                                                                                                                        | no        | -                                                                         | Endpoint redirect for authorization in response to unauthorized requests. Must contain scheme (`http` or `https`) |
| `oauth2.clientId`              | string                                                                                                                        | no        | -                                                                         | The `client_id` to be used in the authorized calls                                                                |
| `oauth2.clientToken`           | string                                                                                                                        | no        | -                                                                         | The `client_secret` used to retrieve the access token                                                             |
| `oauth2.idpAddress`            | string                                                                                                                        | no        | -                                                                         | The address for this socket                                                                                       |
| `oauth2.idpPort`               | string                                                                                                                        | no        | 80                                                                        | The listeners will bind to the port                                                                               |
| `resources`                    | object                                                                                                                        | no        | {requests: {cpu: 50m, memory: 100Mi}, limits: {cpu: 100m, memory: 200Mi}} | Describes computing resource requests and limits for single Pods                                                  |
| `securityContext`              | [core/v1.PodSecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#podsecuritycontext-v1-core) | no        | {}                                                                        | Describes pod-level security attributes                                                                           |
| `containerSecurityContext`     | [core/v1.SecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#securitycontext-v1-core)       | no        | {}                                                                        | Holds container-level security attributes                                                                         |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not recommended parameters.

```yaml
proxy:
  install: true
  image: envoyproxy/envoy:v1.25.8
  type: oauth2

  basic:
    - YWRtaW46YWRtaW4=    # admin:admin encoded in base64
    - dGVzdDp0ZXN0        # test:test  encoded in base64

  oauth2:
    tokenEndpoint: https://example-url.com/token
    authorizationEndpoint: https://example-url.com/auth
    clientId: envoy
    clientToken: envoy
    idpAddress: example-url.com
    idpPort: 80

  resources:
    requests:
      cpu: 50m
      memory: 100Mi
    limits:
      cpu: 100m
      memory: 200Mi
  securityContext:
    runAsUser: 2000
    fsGroup: 2000
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containerSecurityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
```


### Hotrod

`jaeger-hotrod` is a test service that allows to generate of some traces to verify Jaeger's work.

All parameters in the table below should be specified under the key:

```yaml
hotrod:
  install: true
  ...
```

<!-- markdownlint-disable line-length -->
| Parameter                  | Type                                                                                                                          | Mandatory | Default value                                                              | Description                                                                                                                             |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | --------- | -------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `install`                  | boolean                                                                                                                       | no        | false                                                                      | Enabling or disabling creating hotrod deployment                                                                                        |
| `image`                    | string                                                                                                                        | no        | -                                                                          | The docker image to use for a hotrod container                                                                                          |
| `name`                     | string                                                                                                                        | no        | hotrod                                                                     | The name of a microservice to deploy with                                                                                               |
| `imagePullPolicy`          | string                                                                                                                        | no        | IfNotPresent                                                               | The `imagePullPolicy` for a container and the tag of the image affects when the kubelet attempts to pull (download) the specified image |
| `imagePullSecrets`         | object                                                                                                                        | no        | []                                                                         | Keys to access the private registry                                                                                                     |
| `labels`                   | map                                                                                                                           | no        | {}                                                                         | Map of string keys and values that can be used to organize and categorize (scope and select) objects                                    |
| `annotations`              | map                                                                                                                           | no        | {}                                                                         | An unstructured key-value map stored with a resource that may be set by external tools to store and retrieve arbitrary metadata         |
| `otelExporter.host`        | integer                                                                                                                       | no        | -                                                                          | The host used to connect to Open Telemetry Exporter                                                                                     |
| `otelExporter.port`        | integer                                                                                                                       | no        | 14268                                                                      | The port used to connect to Open Telemetry Exporter                                                                                     |
| `nodeSelector`             | map                                                                                                                           | no        | {}                                                                         | Defining which Nodes the Pods are scheduled on                                                                                          |
| `tolerations`              | [core/v1.Toleration](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#toleration-v1-core)                 | no        | {}                                                                         | The pods to schedule onto nodes with matching taints                                                                                    |
| `ingress.install`          | boolean                                                                                                                       | no        | false                                                                      | Enabling or disabling creating a `hotrod` ingress                                                                                       |
| `ingress.host`             | string                                                                                                                        | no        | -                                                                          | The FQDN of the ingress host                                                                                                            |
| `ingress.tls`              | object                                                                                                                        | no        | {}                                                                         | TLS configuration for hotrod ingress                                                                                                    |
| `route.install`            | boolean                                                                                                                       | no        | false                                                                      | Enabling or disabling creating a `hotrod` route                                                                                         |
| `route.host`               | string                                                                                                                        | no        | 0                                                                          | The FQDN of the route host                                                                                                              |
| `service.port`             | integer                                                                                                                       | no        | 80                                                                         | The port for hotrod service                                                                                                             |
| `resources`                | object                                                                                                                        | no        | {requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: 100m, memory: 128Mi}} | Computing resource requests and limits for single Pods                                                                                  |
| `securityContext`          | [core/v1.PodSecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#podsecuritycontext-v1-core) | no        | {}                                                                         | Holds pod-level security attributes                                                                                                     |
| `containerSecurityContext` | [core/v1.SecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#securitycontext-v1-core)       | no        | {}                                                                         | Holds container-level security attributes                                                                                               |
| `priorityClassName`        | string                                                                                                                        | no        | `-`                                                                        | PriorityClassName assigned to the Pods to prevent them from evicting.                                                                   |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not recommended parameters.

```yaml
hotrod:
  install: true
  name: hotrod

  image: jaegertracing/example-hotrod:1.62.0
  imagePullPolicy: IfNotPresent
  imagePullSecrets:
    - name: jaeger-pull-secret

  annotations:
    example.annotation/key: example-annotation-value
  labels:
    example.label/key: example-label-value

  otelExporter:
    host: jaeger-collector
    port: 14268

  # Use in Kubernetes
  ingress:
    install: true
    host: hotrod.cloud.test.org
  # Use in OpenShift
  route:
    install: false
    host: hotrod.cloud.test.org

  resources:
    limits:
      cpu: 100m
      memory: 128Mi
    requests:
      cpu: 100m
      memory: 128Mi
  securityContext:
    runAsUser: 2000
    fsGroup: 2000
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containerSecurityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL

  nodeSelector:
    node-role.kubernetes.io/worker: worker
  tolerations:
    - key: key1
      operator: Equal
      value: value1
      effect: NoSchedule
  priorityClassName: priority-class
```


### Integration Tests

`jaeger-integration-tests` is a service that is used to run integration tests.

All parameters in the table below should be specified under the key:

```yaml
integrationTests:
  install: true
  ...
```

<!-- markdownlint-disable line-length -->
| Parameter                            | Type                                                                                                                          | Mandatory | Default value                                                            | Description                                                                                                                                                                                                                                                                                                                                         |
| ------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- | --------- | ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `install`                            | boolean                                                                                                                       | no        | false                                                                    | Enabling or disabling creating integration tests deployment                                                                                                                                                                                                                                                                                         |
| `image`                              | string                                                                                                                        | no        | -                                                                        | The docker image to use for integration tests container                                                                                                                                                                                                                                                                                             |
| `tags`                               | string                                                                                                                        | no        | smoke                                                                    | Tags combined together with AND, OR and NOT operators that select test cases to run. You can use the "smoke", "generator" and "ha" tags to run the appropriate tests. Or a combination of both, for example smokeORha to run both smoke and ha tests with                                                                                           |
| `linkForGenerator`                   | string                                                                                                                        | no        | `http://jaeger-collector:9411`                                           | Link to host which can get spans in Zipkin format registry                                                                                                                                                                                                                                                                                          |
| `generateCount`                      | integer                                                                                                                       | no        | 10                                                                       | The number of spans which will be sent, 10 by default                                                                                                                                                                                                                                                                                               |
| `waitingTime`                        | string                                                                                                                        | no        | 500ms                                                                    | The waiting time between sending, by default 500ms.                                                                                                                                                                                                                                                                                                 |
| `service.name`                       | string                                                                                                                        | no        | jaeger-integration-tests-runner                                          | The name of the service used to run integration tests.                                                                                                                                                                                                                                                                                              |
| `serviceAccount.create`              | boolean                                                                                                                       | no        | true                                                                     | Specifies whether service account should be created or not.                                                                                                                                                                                                                                                                                         |
| `serviceAccount.name`                | string                                                                                                                        | no        | jaeger-integration-tests                                                 | The name of the service account used to run integration tests.                                                                                                                                                                                                                                                                                      |
| `resources`                          | object                                                                                                                        | no        | {requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 300m, memory: 256Mi}} | Computing resource requests and limits for single Pods                                                                                                                                                                                                                                                                                              |
| `statusWriting.enabled`              | boolean                                                                                                                       | no        | false                                                                    | Parameter to specify whether the status of integration tests results must be written to a custom resource                                                                                                                                                                                                                                           |
| `statusWriting.isShortStatusMessage` | boolean                                                                                                                       | no        | true                                                                     | If it is set to `true`, the `message` field in the status condition by default contains first line from `result.txt` file.                                                                                                                                                                                                                          |
| `statusWriting.onlyIntegrationTests` | boolean                                                                                                                       | no        | true                                                                     | By default, if all tests are passed BDI set `Ready` value to `type` condition field. There is an ability to deploy only integration tests without any component (component was installed before). In this case you should set ONLY_INTEGRATION_TESTS environment variable as true and BDI will set `Successful` as value of `type` condition field. |
| `statusWriting.customResourcePath`   | string                                                                                                                        | no        | apps/v1/jaeger/deployments/jaeger-integration-tests-runner               | Path of Custom Resource where the status of integration tests must be updated                                                                                                                                                                                                                                                                       |
| `securityContext`                    | [core/v1.PodSecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#podsecuritycontext-v1-core) | no        | {}                                                                       | Describes pod-level security attributes                                                                                                                                                                                                                                                                                                             |
| `containerSecurityContext`           | [core/v1.SecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#securitycontext-v1-core)       | no        | {}                                                                       | Holds container-level security attributes                                                                                                                                                                                                                                                                                                           |
| `priorityClassName`                  | string                                                                                                                        | no        | `-`                                                                      | PriorityClassName assigned to the Pods to prevent them from evicting.                                                                                                                                                                                                                                                                               |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not a recommended parameters.

```yaml
integrationTests:
  install: true
  image: "ghcr.io/netcracker/jaeger-integration-tests:main"
  tags: "smokeORha"
  linkForGenerator: "https://jaeger-collector-host"
  generateCount: 10
  waitingTime: 500ms
  resources:
    requests:
      memory: 256Mi
      cpu: 50m
    limits:
      memory: 256Mi
      cpu: 400m
  statusWriting:
    enabled: false
    isShortStatusMessage: true
    onlyIntegrationTests: true
    customResourcePath: "apps/v1/jaeger/deployments/jaeger-integration-tests-runner"
  service:
    name: jaeger-integration-tests-runner
  serviceAccount:
    create: true
    name: "jaeger-integration-tests"
  securityContext:
    runAsUser: 2000
    fsGroup: 2000
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containerSecurityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
  priorityClassName: priority-class
```


### Status Provisioner

`statusProvisioner` is a service that is used to write integration tests results into a job.

All parameters in the table below should be specified under the key:

```yaml
statusProvisioner:
  install: true
  ...
```

<!-- markdownlint-disable line-length -->
| Parameter                  | Type                                                                                                                          | Mandatory | Default value                                                            | Description                                                                                                                  |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | --------- | ------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------- |
| `install`                  | boolean                                                                                                                       | no        | true                                                                     | Status provisioner is always expected to be enabled                                                                          |
| `image`                    | string                                                                                                                        | no        | -                                                                        | The docker image to use for deployment status provisioner container                                                          |
| `lifetimeAfterCompletion`  | integer                                                                                                                       | no        | 300                                                                      | Time until which the staus provisioner job remains active                                                                    |
| `podReadinessTimeout`      | integer                                                                                                                       | no        | 300                                                                      | Timeout in seconds that the Deployment Status Provisioner waits for each of the monitored resources to be ready or completed |
| `integrationTestsTimeout`  | integer                                                                                                                       | no        | 300                                                                      | Timeout in seconds that the Deployment Status Provisioner waits for successful or failed status condition                    |
| `resources`                | object                                                                                                                        | no        | {requests: {cpu: 50m, memory: 50Mi}, limits: {cpu: 100m, memory: 100Mi}} | Computing resource requests and limits for single Pods                                                                       |
| `securityContext`          | [core/v1.PodSecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#podsecuritycontext-v1-core) | no        | {}                                                                       | Describes pod-level security attributes                                                                                      |
| `containerSecurityContext` | [core/v1.SecurityContext](https://kubernetes.io/docs/reference/generated/kubernetes-api/v1.27/#securitycontext-v1-core)       | no        | {}                                                                       | Holds container-level security attributes                                                                                    |
| `priorityClassName`        | string                                                                                                                        | no        | `-`                                                                      | PriorityClassName assigned to the Pods to prevent them from evicting.                                                        |
<!-- markdownlint-enable line-length -->

Examples:

**Note:** It's just an example of a parameter's format, not a recommended parameters.

```yaml
statusProvisioner:
  install: true
  image: ghcr.io/netcracker/qubership-deployment-status-provisioner:main
  lifetimeAfterCompletion: 300
  podReadinessTimeout: 300
  integrationTestsTimeout: 300
  resources:
    requests:
      memory: "50Mi"
      cpu: "50m"
    limits:
      memory: "100Mi"
      cpu: "100m"
  securityContext:
    runAsUser: 2000
    fsGroup: 2000
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containerSecurityContext:
    allowPrivilegeEscalation: false
    capabilities:
      drop:
        - ALL
  priorityClassName: priority-class
```


## Installation

This section describes how to install Jaeger to the Kubernetes.

### Before you begin

* Make sure that selecting Jaeger storage is alive and operable
* Make sure that you configure expected retention data settings

#### Helm

For manual installation, you have to specify images manually in `values.yaml` file.

For example, you can use the following parameters:

```yaml
collector:
  image: jaegertracing/jaeger-collector:1.62.0
query:
  image: jaegertracing/jaeger-query:1.62.0
proxy:
  image: envoyproxy/envoy:v1.25.8
cassandraSchemaJob:
  image: jaegertracing/jaeger-cassandra-schema:1.62.0
hotrod:
  image: jaegertracing/example-hotrod:1.62.0
elasticsearch:
  indexCleaner:
    image: jaegertracing/jaeger-es-index-cleaner:1.62.0
  rollover:
    image: jaegertracing/jaeger-es-rollover:1.62.0
```


### On-prem

This section contains examples of deployment parameters to deploy on-premise Clouds.

#### HA scheme

The minimal template for the HA scheme is as follows:

```yaml
jaeger:
  storage:
    type: cassandra
    
cassandraSchemaJob:
  host: cassandra.cassandra.svc
  keyspace: jaeger
  password: admin
  username: admin
  datacenter: dc1
  mode: prod

query:
  install: true
  replicas: 2

collector:
  install: true
  replicas: 2
```


#### Non-HA scheme

The minimal template for the Non-HA scheme is as follows:

```yaml
jaeger:
  storage:
    type: cassandra
    
cassandraSchemaJob:
  host: cassandra.cassandra.svc
  keyspace: jaeger
  password: admin
  username: admin
  datacenter: dc1

  # This parameter is responsible for with either with SimpleStrategy (without replication)
  # or with NetworkReplicationStrategy (with replication). NetworkReplicationStrategy can be used only
  # if Cassandra cluster has 2 or more nodes.
  # * prod - will use NetworkReplicationStrategy (replication factor = 2)
  # * test - will use SimpleStrategy
  mode: prod

query:
  install: true

collector:
  install: true
```



## Post Deploy Checks

There are some options to check after deploy that Jaeger deployed and working correctly.


### Smoke test

This section contains some steps that can help to check Jaeger's deploy and verify that it has minimal functionality.

Firstly, check deploy and pod statuses of storage used for Jaeger. For example, you can check at least that
all pods are running and didn't restart.

```bash
kubectl get pods -n <namespace>
```

**Note:** In case, when storage will use any managed service like AWS OpenSearch, you need to check that
this service is activated in your account and is working now.

Second, you can check that all components are up using the following command:

```bash
kubectl get pods -n <jaeger_namespace>
```

For example, a typical Jaeger deployment contains the following pods:

```bash
$ kubectl get pods -n tracing
NAME                                    READY   STATUS      RESTARTS   AGE
jaeger-collector-f8c869f8b-jr7tn    1/1     Running     0          4m24s
jaeger-query-7c84bb9c96-cmlh2       1/1     Running     0          4m24s
```

Jaeger deployment also can contain some additional pods like `jaeger-agent` or `jaeger-hotrod`,
but they are optional.

Also, you can see `jaeger-cassandra-schema-job` if execute `kubectl get pods ...` quickly after run deploy.
This job is created by Helm pre-hook and should be removed after successful completion.

Or you can use the Kubernetes Dashboard to see pods and their statuses in the UI.

You can use the command:

```bash
kubectl get pods -n <namespace> --selector=app.kubernetes.io/name=qubership-diag-proxy
```

**Note:** Please pay attention that `qubership-diag-proxy` deployment and pod should be not in the namespace
with Jaeger. It should deploy in the namespace with an application.

If it is presented, you need to check that in environment variables it contains the variable:

```yaml
- name: JAEGER_COLLECTOR_HOST
  value: <jaeger-collector-service>
```

For example:

```yaml
- name: JAEGER_COLLECTOR_HOST
  value: jaeger-collector.jaeger.svc
```

To print a list of environment variables you can use the command:

```bash
kubectl get pods -n <namespace> --selector=app.kubernetes.io/name=qubership-diag-proxy -o yaml
```

Or you can use the Kubernetes Dashboard to check `qubership-diag-proxy` and its settings.

Fourth, you can check that Jaeger has collected the traces using the following command:

```bash
wget -O - http://<jaeger query pod ip or service name>:16686/api/traces/<trace_id>
```

or

```bash
curl -X GET http://<jaeger query pod ip or service name>:16686/api/traces/<trace_id>
```

Or you can use Jaeger UI to check the list of services and traces.
If you don't know any `<trace_id>` you can just try to check that th UI is working now:

```bash
wget -O - http://<jaeger query pod ip or service name>:16686
```

or

```bash
curl -X GET http://<jaeger query pod ip or service name>:16686
```

Or you can use Jaeger UI to check that it works without any errors.

If you have deployed a CloudCore-base application, you can try to find any traces of the `gateway` service.
To find it in UI you need:

* Go to Jaeger UI
* Select `gateway` in the dropdown list of the "Service" parameter
* Click "Find Traces"
* Check that traces collected and available


## Frequently Asked Questions

### Jaeger Sampling Configuration

Jaeger collector sampling configuration can be configured in the `jaeger.serviceName-sampling-configuration` config map.
For more information, refer to _Collector Sampling Configuration Documentation_ at
[https://www.jaegertracing.io/docs/latest/sampling/#collector-sampling-configuration](https://www.jaegertracing.io/docs/latest/sampling/#collector-sampling-configuration).
You need to manually restart collector pods after updating the config map. Updating Jaeger recreates the config map,
so you have to edit it again.

**Note**: The application uses collector sampling configuration only if it is configured to use a remote sampler.
In other cases, the configuration is done on the application side.

