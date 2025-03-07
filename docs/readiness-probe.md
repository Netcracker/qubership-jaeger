# Readiness Probe
## Table of Content

* [Table of Content](#table-of-content)
* [Parameters](#parameters)
* [HWE and Limits](#hwe-and-limits)
* [Command line arguments](#command-line-arguments)

### Parameters

Probe is installed in Kubernetes as a sidecar for extending its probe.

<!-- markdownlint-disable line-length -->
| Parameter             | Type   | Mandatory | Default value          | Description                                                                                   |
|-----------------------|--------| --------- | ---------------------- | --------------------------------------------------------------------------------------------- |
| `namespace`           | String | False     | `tracing`              | The name of the namespace for deploying liveness probe                                        |
| `host`                | String | True      | `-`                    | The host address (`protocol://host:port`) for checking liveness probe                         |
| `port`                | Int    | False     | `-`                    | The port (`protocol://host:port`) for checking liveness probe                                 |
| `authSecretName`      | String | True      | `-`                    | The name of the secret with username and password fields for authorization to access endpoint |
| `caPath`              | String | False     | `-`                    | The path for ca-cert.pem file                                                                 |
| `crtPath`             | String | False     | `-`                    | The path for client-cert.pem file                                                             |
| `keyPath`             | String | False     | `-`                    | The path for client-key.pem file                                                              |
| `tlsEnabled`          | String | False     | `-`                    | Enabling TLS for connection to the storage                                                    |
| `insecureSkipVerify`  | String | False     | `-`                    | Disabling host verification for TLS                                                    |
| `retries`             | Int    | False     | `5`                    | The number of retries for checking liveness probe                                             |
| `errors`              | Int    | False     | `5`                    | The number of allowed errors for checking liveness probe                                      |
| `timeout`             | Int    | False     | `5`                    | The number of seconds for failing liveness probe by timeout                                   |
| `storage`             | String | False     | `cassandra`            | The type of storage in the endpoint, possible values: `cassandra`, `opensearch`               |
| `servicePort`         | Int    | False     | `8080`                 | The port for running liveness-probe container                                                 |
| `shutdownTimeout`     | Int    | False     | `5`                    | The number of seconds for graceful shutdown before connections are cancelled                  |
| `datacenter`          | String | False     | `datacenter1`          | Data center for the Cassandra database                                                        |
| `keyspace`            | String | False     | `jaeger`               | Keyspace for the Cassandra database                                                           |
| `testtable`           | String | False     | `service_names`        | Table name for getting test data from the Cassandra database                                  |
<!-- markdownlint-enable line-length -->

Example:

```shell
/app/probe -endpoint=http://localhost:8080 -authSecretName=auth-secret
```

### HWE and Limits

Probe is installed in Kubernetes as a sidecar container in the pod.

It requires:

* CPU: till 50 millicores
* RAM: till 64 MiB

But usually will use much much less

### Command line arguments

The entrypoint of is `/app/probe`.
