# Observability

Jaeger itself is a distributed, microservices based system. If you run it in production,
you will likely want to setup adequate monitoring for different components,
e.g. to ensure that the backend is not saturated by too much tracing data.

## Table of Content

* [Table of Content](#table-of-content)
* [Monitoring](#monitoring)
  * [Integration with PlatformMonitoring](#integration-with-platformmonitoring)
* [Logging](#logging)
  * [Audit logs](#audit-logs)
  * [Integration with Platform Logging](#integration-with-platform-logging)
* [Traces](#traces)
* [Metrics list](#metrics-list)
  * [Collector](#collector)
  * [Query](#query)

## Monitoring

By default Jaeger microservices expose metrics in Prometheus format.
It is controlled by the following command line options:

* `--admin.http.host-port` the port number where the HTTP admin server is running
* `--metrics-backend` controls how the measurements are exposed. The default value is prometheus,
  another option is expvar, the Go standard mechanism for exposing process level statistics.
* `--metrics-http-route` specifies the name of the HTTP endpoint used to scrape the metrics
  (`/metrics` by default).

Each Jaeger component exposes the metrics scraping endpoint on the admin port:

| Component          | Port  |
| ------------------ | ----- |
| `jaeger-agent`     | 14271 |
| `jaeger-collector` | 14269 |
| `jaeger-query`     | 16687 |
| `jaeger-ingester`  | 14270 |
| `all-in-one`       | 14269 |

<!-- #GFCFilterMarkerStart# -->
[Back to TOC](#table-of-content)
<!-- #GFCFilterMarkerEnd# -->

### Integration with PlatformMonitoring

Jaeger can be deployed with necessary Custom Resources (CR) for Platform Monitoring.

Integration include:

* ServiceMonitor for collector with name "jaeger-collector"
* ServiceMonitor for query with name "jaeger-query"
* ServiceMonitor for agent with name "jaeger-agent"
* ServiceMonitor for proxy with name "proxy-service-monitor"
* GrafanaDashboard with name "Jaeger-Overview"

To install these CRs need add in deploy parameters:

```yaml
jaeger:
  prometheusMonitoring: true
  prometheusMonitoringDashboard: true
```

All necessary configurations will discovery by Prometheus or Grafana automatically.

<!-- #GFCFilterMarkerStart# -->
[Back to TOC](#table-of-content)
<!-- #GFCFilterMarkerEnd# -->

## Logging

Jaeger components only log to standard out, using structured logging library `go.uber.org/zap`
configured to write log lines as JSON encoded strings, for example:

```json
...
{"level":"info","ts":1615914981.7914007,"caller":"flags/admin.go:111","msg":"Starting admin HTTP server","http-addr":":14269"}
{"level":"info","ts":1615914981.7914548,"caller":"flags/admin.go:97","msg":"Admin server started","http.host-port":"[::]:14269","health-status":"unavailable"}
...
```

The log level can be adjusted via `--log-level` command line switch; default level is `info`.

<!-- #GFCFilterMarkerStart# -->
[Back to TOC](#table-of-content)
<!-- #GFCFilterMarkerEnd# -->

### Audit logs

Jaeger has no authentication and authorization as a part of application. Instead, Jaeger's authors offer
to use external tools or proxies to add authentication and/or authorization.

In our solution we are using `Envoy` as proxy to add `Basic Auth` and `OAuth2`. The `Envoy` proxy can be deploy
as a sidecar inside the `jaeger-query`.

The `Envoy` can generate access logs that can be used for audit. Default pattern for access log:

```bash
[%START_TIME%] audit_log_type %REQ(:METHOD)% %REQ(X-ENVOY-ORIGINAL-PATH?:PATH)% %PROTOCOL% %RESPONSE_CODE% %RESPONSE_FLAGS% %BYTES_RECEIVED% %BYTES_SENT% %DURATION% %RESP(X-ENVOY-UPSTREAM-SERVICE-TIME)% %REQ(X-FORWARDED-FOR)% %REQ(USER-AGENT)% %REQ(X-REQUEST-ID)% %REQ(:AUTHORITY)% %UPSTREAM_HOST%
```

Examples of access log:

* Failed login:

  ```bash
  [2024-08-21T08:58:50.838Z] audit_log_type GET /search HTTP/1.1 401 - 0 12 0 - 1.2.3.4 Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36 9bd9eaa74df911b9a1ae0cbafedff031 jaeger.<cloud_dns_name> -
  ```

  The `Envoy` send the `401 Unauthorized` response.

* Successful login:

  ```bash
  [2024-08-21T08:58:50.838Z] audit_log_type GET /search HTTP/1.1 401 - 0 12 0 - 1.2.3.4 Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36 9bd9eaa74df911b9a1ae0cbafedff031 jaeger.<cloud_dns_name> -
  [2024-08-21T08:58:55.248Z] audit_log_type GET /search HTTP/1.1 200 - 0 1980 1 0 1.2.3.4 Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36 d27418272ca7c56db7109b8215a51900 jaeger.<cloud_dns_name> 127.0.0.1:16686
  ```

  The `Envoy` firstly send the `401 Unauthorized` response and trigger browser to show authentication form,
  after send the correct credentials pass user to UI.

The `Envoy` will log all requests from UI in access logs.

<!-- #GFCFilterMarkerStart# -->
[Back to TOC](#table-of-content)
<!-- #GFCFilterMarkerEnd# -->

### Integration with Platform Logging

Integration Jaeger with logging doesn't require any specify actions. All works out of the box
if logging agent deployed in Cloud and collect logs from pods.

In Graylog you can use next queries for find Jaeger logs:

* Stream "All messages", filter by namespace name:

```yaml
namespace_name: <namespace>
## for example:
## namespace_name: tracing
```

* Stream "All messages", filter by pod name:

```yaml
pod_name: <pod>
## for example:
## pods_name: jaeger-collector-7bb5bcd6d4-qlqhh
```

<!-- #GFCFilterMarkerStart# -->
[Back to TOC](#table-of-content)
<!-- #GFCFilterMarkerEnd# -->

## Traces

Jaeger has the ability to trace some of its own components, namely the requests to the Query
service. For example, if you start `all-in-one` as described in Getting Started, and refresh
the UI screen a few times, you will see `jaeger-query` populated in the Services dropdown.
If you prefer not to see these traces in the Jaeger UI, you can disable them by running
Jaeger backend components with `JAEGER_DISABLED=true` environment variable, for example:

```bash
docker run -e JAEGER_DISABLED=true -p 16686:16686 jaegertracing/all-in-one:1.33
```

<!-- #GFCFilterMarkerStart# -->
[Back to TOC](#table-of-content)
<!-- #GFCFilterMarkerEnd# -->

## Metrics list

### Collector

<details>
  <summary>Collector metrics</summary>

<!-- markdownlint-disable line-length -->
```prometheus
## HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
## TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 4.233e-05
go_gc_duration_seconds{quantile="0.25"} 7.7418e-05
go_gc_duration_seconds{quantile="0.5"} 0.000108891
go_gc_duration_seconds{quantile="0.75"} 0.000148936
go_gc_duration_seconds{quantile="1"} 0.001421994
go_gc_duration_seconds_sum 0.004580071
go_gc_duration_seconds_count 29
## HELP go_goroutines Number of goroutines that currently exist.
## TYPE go_goroutines gauge
go_goroutines 98
## HELP go_info Information about the Go environment.
## TYPE go_info gauge
go_info{version="go1.20.5"} 1
## HELP go_memstats_alloc_bytes Number of bytes allocated and still in use.
## TYPE go_memstats_alloc_bytes gauge
go_memstats_alloc_bytes 4.717048e+06
## HELP go_memstats_alloc_bytes_total Total number of bytes allocated, even if freed.
## TYPE go_memstats_alloc_bytes_total counter
go_memstats_alloc_bytes_total 1.00601176e+08
## HELP go_memstats_buck_hash_sys_bytes Number of bytes used by the profiling bucket hash table.
## TYPE go_memstats_buck_hash_sys_bytes gauge
go_memstats_buck_hash_sys_bytes 1.482038e+06
## HELP go_memstats_frees_total Total number of frees.
## TYPE go_memstats_frees_total counter
go_memstats_frees_total 1.365496e+06
## HELP go_memstats_gc_sys_bytes Number of bytes used for garbage collection system metadata.
## TYPE go_memstats_gc_sys_bytes gauge
go_memstats_gc_sys_bytes 8.862624e+06
## HELP go_memstats_heap_alloc_bytes Number of heap bytes allocated and still in use.
## TYPE go_memstats_heap_alloc_bytes gauge
go_memstats_heap_alloc_bytes 4.717048e+06
## HELP go_memstats_heap_idle_bytes Number of heap bytes waiting to be used.
## TYPE go_memstats_heap_idle_bytes gauge
go_memstats_heap_idle_bytes 4.521984e+06
## HELP go_memstats_heap_inuse_bytes Number of heap bytes that are in use.
## TYPE go_memstats_heap_inuse_bytes gauge
go_memstats_heap_inuse_bytes 6.750208e+06
## HELP go_memstats_heap_objects Number of allocated objects.
## TYPE go_memstats_heap_objects gauge
go_memstats_heap_objects 35753
## HELP go_memstats_heap_released_bytes Number of heap bytes released to OS.
## TYPE go_memstats_heap_released_bytes gauge
go_memstats_heap_released_bytes 2.097152e+06
## HELP go_memstats_heap_sys_bytes Number of heap bytes obtained from system.
## TYPE go_memstats_heap_sys_bytes gauge
go_memstats_heap_sys_bytes 1.1272192e+07
## HELP go_memstats_last_gc_time_seconds Number of seconds since 1970 of last garbage collection.
## TYPE go_memstats_last_gc_time_seconds gauge
go_memstats_last_gc_time_seconds 1.692017462958174e+09
## HELP go_memstats_lookups_total Total number of pointer lookups.
## TYPE go_memstats_lookups_total counter
go_memstats_lookups_total 0
## HELP go_memstats_mallocs_total Total number of mallocs.
## TYPE go_memstats_mallocs_total counter
go_memstats_mallocs_total 1.401249e+06
## HELP go_memstats_mcache_inuse_bytes Number of bytes in use by mcache structures.
## TYPE go_memstats_mcache_inuse_bytes gauge
go_memstats_mcache_inuse_bytes 1200
## HELP go_memstats_mcache_sys_bytes Number of bytes used for mcache structures obtained from system.
## TYPE go_memstats_mcache_sys_bytes gauge
go_memstats_mcache_sys_bytes 15600
## HELP go_memstats_mspan_inuse_bytes Number of bytes in use by mspan structures.
## TYPE go_memstats_mspan_inuse_bytes gauge
go_memstats_mspan_inuse_bytes 111520
## HELP go_memstats_mspan_sys_bytes Number of bytes used for mspan structures obtained from system.
## TYPE go_memstats_mspan_sys_bytes gauge
go_memstats_mspan_sys_bytes 146880
## HELP go_memstats_next_gc_bytes Number of heap bytes when next garbage collection will take place.
## TYPE go_memstats_next_gc_bytes gauge
go_memstats_next_gc_bytes 8.130136e+06
## HELP go_memstats_other_sys_bytes Number of bytes used for other system allocations.
## TYPE go_memstats_other_sys_bytes gauge
go_memstats_other_sys_bytes 631170
## HELP go_memstats_stack_inuse_bytes Number of bytes in use by the stack allocator.
## TYPE go_memstats_stack_inuse_bytes gauge
go_memstats_stack_inuse_bytes 1.31072e+06
## HELP go_memstats_stack_sys_bytes Number of bytes obtained from system for stack allocator.
## TYPE go_memstats_stack_sys_bytes gauge
go_memstats_stack_sys_bytes 1.31072e+06
## HELP go_memstats_sys_bytes Number of bytes obtained from system.
## TYPE go_memstats_sys_bytes gauge
go_memstats_sys_bytes 2.3721224e+07
## HELP go_threads Number of OS threads created.
## TYPE go_threads gauge
go_threads 7
## HELP jaeger_cassandra_attempts_total attempts
## TYPE jaeger_cassandra_attempts_total counter
jaeger_cassandra_attempts_total{table="duration_index"} 1078
jaeger_cassandra_attempts_total{table="operation_names"} 1
jaeger_cassandra_attempts_total{table="service_name_index"} 539
jaeger_cassandra_attempts_total{table="service_names"} 1
jaeger_cassandra_attempts_total{table="service_operation_index"} 539
jaeger_cassandra_attempts_total{table="tag_index"} 3773
jaeger_cassandra_attempts_total{table="traces"} 540
## HELP jaeger_cassandra_errors_total errors
## TYPE jaeger_cassandra_errors_total counter
jaeger_cassandra_errors_total{table="duration_index"} 0
jaeger_cassandra_errors_total{table="operation_names"} 1
jaeger_cassandra_errors_total{table="service_name_index"} 0
jaeger_cassandra_errors_total{table="service_names"} 0
jaeger_cassandra_errors_total{table="service_operation_index"} 0
jaeger_cassandra_errors_total{table="tag_index"} 0
jaeger_cassandra_errors_total{table="traces"} 0
## HELP jaeger_cassandra_inserts_total inserts
## TYPE jaeger_cassandra_inserts_total counter
jaeger_cassandra_inserts_total{table="duration_index"} 1078
jaeger_cassandra_inserts_total{table="operation_names"} 0
jaeger_cassandra_inserts_total{table="service_name_index"} 539
jaeger_cassandra_inserts_total{table="service_names"} 1
jaeger_cassandra_inserts_total{table="service_operation_index"} 539
jaeger_cassandra_inserts_total{table="tag_index"} 3773
jaeger_cassandra_inserts_total{table="traces"} 540
## HELP jaeger_cassandra_latency_err latency-err
## TYPE jaeger_cassandra_latency_err histogram
jaeger_cassandra_latency_err_bucket{table="duration_index",le="0.005"} 0
jaeger_cassandra_latency_err_bucket{table="duration_index",le="0.01"} 0
jaeger_cassandra_latency_err_bucket{table="duration_index",le="0.025"} 0
jaeger_cassandra_latency_err_bucket{table="duration_index",le="0.05"} 0
jaeger_cassandra_latency_err_bucket{table="duration_index",le="0.1"} 0
jaeger_cassandra_latency_err_bucket{table="duration_index",le="0.25"} 0
jaeger_cassandra_latency_err_bucket{table="duration_index",le="0.5"} 0
jaeger_cassandra_latency_err_bucket{table="duration_index",le="1"} 0
jaeger_cassandra_latency_err_bucket{table="duration_index",le="2.5"} 0
jaeger_cassandra_latency_err_bucket{table="duration_index",le="5"} 0
jaeger_cassandra_latency_err_bucket{table="duration_index",le="10"} 0
jaeger_cassandra_latency_err_bucket{table="duration_index",le="+Inf"} 0
jaeger_cassandra_latency_err_sum{table="duration_index"} 0
jaeger_cassandra_latency_err_count{table="duration_index"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.005"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.01"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.025"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.05"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.1"} 1
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.25"} 1
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.5"} 1
jaeger_cassandra_latency_err_bucket{table="operation_names",le="1"} 1
jaeger_cassandra_latency_err_bucket{table="operation_names",le="2.5"} 1
jaeger_cassandra_latency_err_bucket{table="operation_names",le="5"} 1
jaeger_cassandra_latency_err_bucket{table="operation_names",le="10"} 1
jaeger_cassandra_latency_err_bucket{table="operation_names",le="+Inf"} 1
jaeger_cassandra_latency_err_sum{table="operation_names"} 0.088707462
jaeger_cassandra_latency_err_count{table="operation_names"} 1
jaeger_cassandra_latency_err_bucket{table="service_name_index",le="0.005"} 0
jaeger_cassandra_latency_err_bucket{table="service_name_index",le="0.01"} 0
jaeger_cassandra_latency_err_bucket{table="service_name_index",le="0.025"} 0
jaeger_cassandra_latency_err_bucket{table="service_name_index",le="0.05"} 0
jaeger_cassandra_latency_err_bucket{table="service_name_index",le="0.1"} 0
jaeger_cassandra_latency_err_bucket{table="service_name_index",le="0.25"} 0
jaeger_cassandra_latency_err_bucket{table="service_name_index",le="0.5"} 0
jaeger_cassandra_latency_err_bucket{table="service_name_index",le="1"} 0
jaeger_cassandra_latency_err_bucket{table="service_name_index",le="2.5"} 0
jaeger_cassandra_latency_err_bucket{table="service_name_index",le="5"} 0
jaeger_cassandra_latency_err_bucket{table="service_name_index",le="10"} 0
jaeger_cassandra_latency_err_bucket{table="service_name_index",le="+Inf"} 0
jaeger_cassandra_latency_err_sum{table="service_name_index"} 0
jaeger_cassandra_latency_err_count{table="service_name_index"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.005"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.01"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.025"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.05"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.1"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.25"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.5"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="1"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="2.5"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="5"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="10"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="+Inf"} 0
jaeger_cassandra_latency_err_sum{table="service_names"} 0
jaeger_cassandra_latency_err_count{table="service_names"} 0
jaeger_cassandra_latency_err_bucket{table="service_operation_index",le="0.005"} 0
jaeger_cassandra_latency_err_bucket{table="service_operation_index",le="0.01"} 0
jaeger_cassandra_latency_err_bucket{table="service_operation_index",le="0.025"} 0
jaeger_cassandra_latency_err_bucket{table="service_operation_index",le="0.05"} 0
jaeger_cassandra_latency_err_bucket{table="service_operation_index",le="0.1"} 0
jaeger_cassandra_latency_err_bucket{table="service_operation_index",le="0.25"} 0
jaeger_cassandra_latency_err_bucket{table="service_operation_index",le="0.5"} 0
jaeger_cassandra_latency_err_bucket{table="service_operation_index",le="1"} 0
jaeger_cassandra_latency_err_bucket{table="service_operation_index",le="2.5"} 0
jaeger_cassandra_latency_err_bucket{table="service_operation_index",le="5"} 0
jaeger_cassandra_latency_err_bucket{table="service_operation_index",le="10"} 0
jaeger_cassandra_latency_err_bucket{table="service_operation_index",le="+Inf"} 0
jaeger_cassandra_latency_err_sum{table="service_operation_index"} 0
jaeger_cassandra_latency_err_count{table="service_operation_index"} 0
jaeger_cassandra_latency_err_bucket{table="tag_index",le="0.005"} 0
jaeger_cassandra_latency_err_bucket{table="tag_index",le="0.01"} 0
jaeger_cassandra_latency_err_bucket{table="tag_index",le="0.025"} 0
jaeger_cassandra_latency_err_bucket{table="tag_index",le="0.05"} 0
jaeger_cassandra_latency_err_bucket{table="tag_index",le="0.1"} 0
jaeger_cassandra_latency_err_bucket{table="tag_index",le="0.25"} 0
jaeger_cassandra_latency_err_bucket{table="tag_index",le="0.5"} 0
jaeger_cassandra_latency_err_bucket{table="tag_index",le="1"} 0
jaeger_cassandra_latency_err_bucket{table="tag_index",le="2.5"} 0
jaeger_cassandra_latency_err_bucket{table="tag_index",le="5"} 0
jaeger_cassandra_latency_err_bucket{table="tag_index",le="10"} 0
jaeger_cassandra_latency_err_bucket{table="tag_index",le="+Inf"} 0
jaeger_cassandra_latency_err_sum{table="tag_index"} 0
jaeger_cassandra_latency_err_count{table="tag_index"} 0
jaeger_cassandra_latency_err_bucket{table="traces",le="0.005"} 0
jaeger_cassandra_latency_err_bucket{table="traces",le="0.01"} 0
jaeger_cassandra_latency_err_bucket{table="traces",le="0.025"} 0
jaeger_cassandra_latency_err_bucket{table="traces",le="0.05"} 0
jaeger_cassandra_latency_err_bucket{table="traces",le="0.1"} 0
jaeger_cassandra_latency_err_bucket{table="traces",le="0.25"} 0
jaeger_cassandra_latency_err_bucket{table="traces",le="0.5"} 0
jaeger_cassandra_latency_err_bucket{table="traces",le="1"} 0
jaeger_cassandra_latency_err_bucket{table="traces",le="2.5"} 0
jaeger_cassandra_latency_err_bucket{table="traces",le="5"} 0
jaeger_cassandra_latency_err_bucket{table="traces",le="10"} 0
jaeger_cassandra_latency_err_bucket{table="traces",le="+Inf"} 0
jaeger_cassandra_latency_err_sum{table="traces"} 0
jaeger_cassandra_latency_err_count{table="traces"} 0
## HELP jaeger_cassandra_latency_ok latency-ok
## TYPE jaeger_cassandra_latency_ok histogram
jaeger_cassandra_latency_ok_bucket{table="duration_index",le="0.005"} 536
jaeger_cassandra_latency_ok_bucket{table="duration_index",le="0.01"} 794
jaeger_cassandra_latency_ok_bucket{table="duration_index",le="0.025"} 996
jaeger_cassandra_latency_ok_bucket{table="duration_index",le="0.05"} 1054
jaeger_cassandra_latency_ok_bucket{table="duration_index",le="0.1"} 1077
jaeger_cassandra_latency_ok_bucket{table="duration_index",le="0.25"} 1077
jaeger_cassandra_latency_ok_bucket{table="duration_index",le="0.5"} 1078
jaeger_cassandra_latency_ok_bucket{table="duration_index",le="1"} 1078
jaeger_cassandra_latency_ok_bucket{table="duration_index",le="2.5"} 1078
jaeger_cassandra_latency_ok_bucket{table="duration_index",le="5"} 1078
jaeger_cassandra_latency_ok_bucket{table="duration_index",le="10"} 1078
jaeger_cassandra_latency_ok_bucket{table="duration_index",le="+Inf"} 1078
jaeger_cassandra_latency_ok_sum{table="duration_index"} 10.333384656000003
jaeger_cassandra_latency_ok_count{table="duration_index"} 1078
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.005"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.01"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.025"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.05"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.1"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.25"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.5"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="1"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="2.5"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="5"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="10"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="+Inf"} 0
jaeger_cassandra_latency_ok_sum{table="operation_names"} 0
jaeger_cassandra_latency_ok_count{table="operation_names"} 0
jaeger_cassandra_latency_ok_bucket{table="service_name_index",le="0.005"} 133
jaeger_cassandra_latency_ok_bucket{table="service_name_index",le="0.01"} 356
jaeger_cassandra_latency_ok_bucket{table="service_name_index",le="0.025"} 517
jaeger_cassandra_latency_ok_bucket{table="service_name_index",le="0.05"} 531
jaeger_cassandra_latency_ok_bucket{table="service_name_index",le="0.1"} 538
jaeger_cassandra_latency_ok_bucket{table="service_name_index",le="0.25"} 539
jaeger_cassandra_latency_ok_bucket{table="service_name_index",le="0.5"} 539
jaeger_cassandra_latency_ok_bucket{table="service_name_index",le="1"} 539
jaeger_cassandra_latency_ok_bucket{table="service_name_index",le="2.5"} 539
jaeger_cassandra_latency_ok_bucket{table="service_name_index",le="5"} 539
jaeger_cassandra_latency_ok_bucket{table="service_name_index",le="10"} 539
jaeger_cassandra_latency_ok_bucket{table="service_name_index",le="+Inf"} 539
jaeger_cassandra_latency_ok_sum{table="service_name_index"} 5.694438255999998
jaeger_cassandra_latency_ok_count{table="service_name_index"} 539
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.005"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.01"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.025"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.05"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.1"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.25"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.5"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="1"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="2.5"} 1
jaeger_cassandra_latency_ok_bucket{table="service_names",le="5"} 1
jaeger_cassandra_latency_ok_bucket{table="service_names",le="10"} 1
jaeger_cassandra_latency_ok_bucket{table="service_names",le="+Inf"} 1
jaeger_cassandra_latency_ok_sum{table="service_names"} 1.048394961
jaeger_cassandra_latency_ok_count{table="service_names"} 1
jaeger_cassandra_latency_ok_bucket{table="service_operation_index",le="0.005"} 228
jaeger_cassandra_latency_ok_bucket{table="service_operation_index",le="0.01"} 406
jaeger_cassandra_latency_ok_bucket{table="service_operation_index",le="0.025"} 525
jaeger_cassandra_latency_ok_bucket{table="service_operation_index",le="0.05"} 537
jaeger_cassandra_latency_ok_bucket{table="service_operation_index",le="0.1"} 538
jaeger_cassandra_latency_ok_bucket{table="service_operation_index",le="0.25"} 539
jaeger_cassandra_latency_ok_bucket{table="service_operation_index",le="0.5"} 539
jaeger_cassandra_latency_ok_bucket{table="service_operation_index",le="1"} 539
jaeger_cassandra_latency_ok_bucket{table="service_operation_index",le="2.5"} 539
jaeger_cassandra_latency_ok_bucket{table="service_operation_index",le="5"} 539
jaeger_cassandra_latency_ok_bucket{table="service_operation_index",le="10"} 539
jaeger_cassandra_latency_ok_bucket{table="service_operation_index",le="+Inf"} 539
jaeger_cassandra_latency_ok_sum{table="service_operation_index"} 4.4824353589999975
jaeger_cassandra_latency_ok_count{table="service_operation_index"} 539
jaeger_cassandra_latency_ok_bucket{table="tag_index",le="0.005"} 2352
jaeger_cassandra_latency_ok_bucket{table="tag_index",le="0.01"} 3164
jaeger_cassandra_latency_ok_bucket{table="tag_index",le="0.025"} 3671
jaeger_cassandra_latency_ok_bucket{table="tag_index",le="0.05"} 3742
jaeger_cassandra_latency_ok_bucket{table="tag_index",le="0.1"} 3770
jaeger_cassandra_latency_ok_bucket{table="tag_index",le="0.25"} 3773
jaeger_cassandra_latency_ok_bucket{table="tag_index",le="0.5"} 3773
jaeger_cassandra_latency_ok_bucket{table="tag_index",le="1"} 3773
jaeger_cassandra_latency_ok_bucket{table="tag_index",le="2.5"} 3773
jaeger_cassandra_latency_ok_bucket{table="tag_index",le="5"} 3773
jaeger_cassandra_latency_ok_bucket{table="tag_index",le="10"} 3773
jaeger_cassandra_latency_ok_bucket{table="tag_index",le="+Inf"} 3773
jaeger_cassandra_latency_ok_sum{table="tag_index"} 25.012430945999984
jaeger_cassandra_latency_ok_count{table="tag_index"} 3773
jaeger_cassandra_latency_ok_bucket{table="traces",le="0.005"} 5
jaeger_cassandra_latency_ok_bucket{table="traces",le="0.01"} 232
jaeger_cassandra_latency_ok_bucket{table="traces",le="0.025"} 477
jaeger_cassandra_latency_ok_bucket{table="traces",le="0.05"} 534
jaeger_cassandra_latency_ok_bucket{table="traces",le="0.1"} 537
jaeger_cassandra_latency_ok_bucket{table="traces",le="0.25"} 538
jaeger_cassandra_latency_ok_bucket{table="traces",le="0.5"} 538
jaeger_cassandra_latency_ok_bucket{table="traces",le="1"} 540
jaeger_cassandra_latency_ok_bucket{table="traces",le="2.5"} 540
jaeger_cassandra_latency_ok_bucket{table="traces",le="5"} 540
jaeger_cassandra_latency_ok_bucket{table="traces",le="10"} 540
jaeger_cassandra_latency_ok_bucket{table="traces",le="+Inf"} 540
jaeger_cassandra_latency_ok_sum{table="traces"} 9.093478506999991
jaeger_cassandra_latency_ok_count{table="traces"} 540
## HELP jaeger_cassandra_tag_index_skipped_total tag_index_skipped
## TYPE jaeger_cassandra_tag_index_skipped_total counter
jaeger_cassandra_tag_index_skipped_total 0
## HELP jaeger_collector_batch_size batch-size
## TYPE jaeger_collector_batch_size gauge
jaeger_collector_batch_size{host="jaeger-collector-7ff95f55cf-mkt75"} 2
## HELP jaeger_collector_build_info build_info
## TYPE jaeger_collector_build_info gauge
jaeger_collector_build_info{build_date="2023-07-06T20:38:11Z",revision="ee6cc41ef62ba8f04de8a16431b43b620bdf571c",version="v1.62.0"} 1
## HELP jaeger_collector_http_request_duration Duration of HTTP requests
## TYPE jaeger_collector_http_request_duration histogram
jaeger_collector_http_request_duration_bucket{method="POST",path="/api/traces",status="202",le="0.005"} 271
jaeger_collector_http_request_duration_bucket{method="POST",path="/api/traces",status="202",le="0.01"} 271
jaeger_collector_http_request_duration_bucket{method="POST",path="/api/traces",status="202",le="0.025"} 271
jaeger_collector_http_request_duration_bucket{method="POST",path="/api/traces",status="202",le="0.05"} 271
jaeger_collector_http_request_duration_bucket{method="POST",path="/api/traces",status="202",le="0.1"} 271
jaeger_collector_http_request_duration_bucket{method="POST",path="/api/traces",status="202",le="0.25"} 271
jaeger_collector_http_request_duration_bucket{method="POST",path="/api/traces",status="202",le="0.5"} 271
jaeger_collector_http_request_duration_bucket{method="POST",path="/api/traces",status="202",le="1"} 271
jaeger_collector_http_request_duration_bucket{method="POST",path="/api/traces",status="202",le="2.5"} 271
jaeger_collector_http_request_duration_bucket{method="POST",path="/api/traces",status="202",le="5"} 271
jaeger_collector_http_request_duration_bucket{method="POST",path="/api/traces",status="202",le="10"} 271
jaeger_collector_http_request_duration_bucket{method="POST",path="/api/traces",status="202",le="+Inf"} 271
jaeger_collector_http_request_duration_sum{method="POST",path="/api/traces",status="202"} 0.038305274999999965
jaeger_collector_http_request_duration_count{method="POST",path="/api/traces",status="202"} 271
jaeger_collector_http_request_duration_bucket{method="other",path="other",status="other",le="0.005"} 0
jaeger_collector_http_request_duration_bucket{method="other",path="other",status="other",le="0.01"} 0
jaeger_collector_http_request_duration_bucket{method="other",path="other",status="other",le="0.025"} 0
jaeger_collector_http_request_duration_bucket{method="other",path="other",status="other",le="0.05"} 0
jaeger_collector_http_request_duration_bucket{method="other",path="other",status="other",le="0.1"} 0
jaeger_collector_http_request_duration_bucket{method="other",path="other",status="other",le="0.25"} 0
jaeger_collector_http_request_duration_bucket{method="other",path="other",status="other",le="0.5"} 0
jaeger_collector_http_request_duration_bucket{method="other",path="other",status="other",le="1"} 0
jaeger_collector_http_request_duration_bucket{method="other",path="other",status="other",le="2.5"} 0
jaeger_collector_http_request_duration_bucket{method="other",path="other",status="other",le="5"} 0
jaeger_collector_http_request_duration_bucket{method="other",path="other",status="other",le="10"} 0
jaeger_collector_http_request_duration_bucket{method="other",path="other",status="other",le="+Inf"} 0
jaeger_collector_http_request_duration_sum{method="other",path="other",status="other"} 0
jaeger_collector_http_request_duration_count{method="other",path="other",status="other"} 0
## HELP jaeger_collector_http_server_errors_total http-server.errors
## TYPE jaeger_collector_http_server_errors_total counter
jaeger_collector_http_server_errors_total{source="all",status="4xx"} 0
jaeger_collector_http_server_errors_total{source="collector-proxy",status="5xx"} 0
jaeger_collector_http_server_errors_total{source="proto",status="5xx"} 0
jaeger_collector_http_server_errors_total{source="thrift",status="5xx"} 0
jaeger_collector_http_server_errors_total{source="write",status="5xx"} 0
## HELP jaeger_collector_http_server_requests_total http-server.requests
## TYPE jaeger_collector_http_server_requests_total counter
jaeger_collector_http_server_requests_total{type="baggage"} 0
jaeger_collector_http_server_requests_total{type="sampling"} 0
jaeger_collector_http_server_requests_total{type="sampling-legacy"} 0
## HELP jaeger_collector_in_queue_latency in-queue-latency
## TYPE jaeger_collector_in_queue_latency histogram
jaeger_collector_in_queue_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.005"} 0
jaeger_collector_in_queue_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.01"} 0
jaeger_collector_in_queue_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.025"} 0
jaeger_collector_in_queue_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.05"} 12
jaeger_collector_in_queue_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.1"} 355
jaeger_collector_in_queue_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.25"} 534
jaeger_collector_in_queue_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.5"} 538
jaeger_collector_in_queue_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="1"} 539
jaeger_collector_in_queue_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="2.5"} 539
jaeger_collector_in_queue_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="5"} 540
jaeger_collector_in_queue_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="10"} 540
jaeger_collector_in_queue_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="+Inf"} 540
jaeger_collector_in_queue_latency_sum{host="jaeger-collector-7ff95f55cf-mkt75"} 56.111491801
jaeger_collector_in_queue_latency_count{host="jaeger-collector-7ff95f55cf-mkt75"} 540
## HELP jaeger_collector_queue_capacity queue-capacity
## TYPE jaeger_collector_queue_capacity gauge
jaeger_collector_queue_capacity{host="jaeger-collector-7ff95f55cf-mkt75"} 2000
## HELP jaeger_collector_queue_length queue-length
## TYPE jaeger_collector_queue_length gauge
jaeger_collector_queue_length{host="jaeger-collector-7ff95f55cf-mkt75"} 0
## HELP jaeger_collector_save_latency save-latency
## TYPE jaeger_collector_save_latency histogram
jaeger_collector_save_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.005"} 0
jaeger_collector_save_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.01"} 0
jaeger_collector_save_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.025"} 0
jaeger_collector_save_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.05"} 12
jaeger_collector_save_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.1"} 359
jaeger_collector_save_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.25"} 534
jaeger_collector_save_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="0.5"} 538
jaeger_collector_save_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="1"} 539
jaeger_collector_save_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="2.5"} 539
jaeger_collector_save_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="5"} 540
jaeger_collector_save_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="10"} 540
jaeger_collector_save_latency_bucket{host="jaeger-collector-7ff95f55cf-mkt75",le="+Inf"} 540
jaeger_collector_save_latency_sum{host="jaeger-collector-7ff95f55cf-mkt75"} 55.93221145900002
jaeger_collector_save_latency_count{host="jaeger-collector-7ff95f55cf-mkt75"} 540
## HELP jaeger_collector_spans_bytes spans.bytes
## TYPE jaeger_collector_spans_bytes gauge
jaeger_collector_spans_bytes{host="jaeger-collector-7ff95f55cf-mkt75"} 0
## HELP jaeger_collector_spans_dropped_total spans.dropped
## TYPE jaeger_collector_spans_dropped_total counter
jaeger_collector_spans_dropped_total{host="jaeger-collector-7ff95f55cf-mkt75"} 0
## HELP jaeger_collector_spans_received_total received
## TYPE jaeger_collector_spans_received_total counter
jaeger_collector_spans_received_total{debug="false",format="jaeger",svc="frontend",transport="http"} 540
jaeger_collector_spans_received_total{debug="false",format="jaeger",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_received_total{debug="false",format="jaeger",svc="other-services",transport="http"} 0
jaeger_collector_spans_received_total{debug="false",format="jaeger",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_received_total{debug="false",format="proto",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_received_total{debug="false",format="proto",svc="other-services",transport="http"} 0
jaeger_collector_spans_received_total{debug="false",format="proto",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_received_total{debug="false",format="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_received_total{debug="false",format="unknown",svc="other-services",transport="http"} 0
jaeger_collector_spans_received_total{debug="false",format="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_received_total{debug="false",format="zipkin",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_received_total{debug="false",format="zipkin",svc="other-services",transport="http"} 0
jaeger_collector_spans_received_total{debug="false",format="zipkin",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_received_total{debug="true",format="jaeger",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_received_total{debug="true",format="jaeger",svc="other-services",transport="http"} 0
jaeger_collector_spans_received_total{debug="true",format="jaeger",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_received_total{debug="true",format="proto",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_received_total{debug="true",format="proto",svc="other-services",transport="http"} 0
jaeger_collector_spans_received_total{debug="true",format="proto",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_received_total{debug="true",format="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_received_total{debug="true",format="unknown",svc="other-services",transport="http"} 0
jaeger_collector_spans_received_total{debug="true",format="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_received_total{debug="true",format="zipkin",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_received_total{debug="true",format="zipkin",svc="other-services",transport="http"} 0
jaeger_collector_spans_received_total{debug="true",format="zipkin",svc="other-services",transport="unknown"} 0
## HELP jaeger_collector_spans_rejected_total rejected
## TYPE jaeger_collector_spans_rejected_total counter
jaeger_collector_spans_rejected_total{debug="false",format="jaeger",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_rejected_total{debug="false",format="jaeger",svc="other-services",transport="http"} 0
jaeger_collector_spans_rejected_total{debug="false",format="jaeger",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_rejected_total{debug="false",format="proto",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_rejected_total{debug="false",format="proto",svc="other-services",transport="http"} 0
jaeger_collector_spans_rejected_total{debug="false",format="proto",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_rejected_total{debug="false",format="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_rejected_total{debug="false",format="unknown",svc="other-services",transport="http"} 0
jaeger_collector_spans_rejected_total{debug="false",format="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_rejected_total{debug="false",format="zipkin",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_rejected_total{debug="false",format="zipkin",svc="other-services",transport="http"} 0
jaeger_collector_spans_rejected_total{debug="false",format="zipkin",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_rejected_total{debug="true",format="jaeger",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_rejected_total{debug="true",format="jaeger",svc="other-services",transport="http"} 0
jaeger_collector_spans_rejected_total{debug="true",format="jaeger",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_rejected_total{debug="true",format="proto",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_rejected_total{debug="true",format="proto",svc="other-services",transport="http"} 0
jaeger_collector_spans_rejected_total{debug="true",format="proto",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_rejected_total{debug="true",format="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_rejected_total{debug="true",format="unknown",svc="other-services",transport="http"} 0
jaeger_collector_spans_rejected_total{debug="true",format="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_spans_rejected_total{debug="true",format="zipkin",svc="other-services",transport="grpc"} 0
jaeger_collector_spans_rejected_total{debug="true",format="zipkin",svc="other-services",transport="http"} 0
jaeger_collector_spans_rejected_total{debug="true",format="zipkin",svc="other-services",transport="unknown"} 0
## HELP jaeger_collector_spans_saved_by_svc_total saved-by-svc
## TYPE jaeger_collector_spans_saved_by_svc_total counter
jaeger_collector_spans_saved_by_svc_total{debug="false",result="err",svc="frontend"} 1
jaeger_collector_spans_saved_by_svc_total{debug="false",result="err",svc="other-services"} 0
jaeger_collector_spans_saved_by_svc_total{debug="false",result="ok",svc="frontend"} 539
jaeger_collector_spans_saved_by_svc_total{debug="false",result="ok",svc="other-services"} 0
jaeger_collector_spans_saved_by_svc_total{debug="true",result="err",svc="other-services"} 0
jaeger_collector_spans_saved_by_svc_total{debug="true",result="ok",svc="other-services"} 0
## HELP jaeger_collector_spans_serviceNames spans.serviceNames
## TYPE jaeger_collector_spans_serviceNames gauge
jaeger_collector_spans_serviceNames{host="jaeger-collector-7ff95f55cf-mkt75"} 0
## HELP jaeger_collector_traces_received_total received
## TYPE jaeger_collector_traces_received_total counter
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="unknown",svc="frontend",transport="http"} 540
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="jaeger",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="proto",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="unknown",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="false",format="zipkin",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="jaeger",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="proto",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="unknown",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_received_total{debug="true",format="zipkin",sampler_type="unknown",svc="other-services",transport="unknown"} 0
## HELP jaeger_collector_traces_rejected_total rejected
## TYPE jaeger_collector_traces_rejected_total counter
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="jaeger",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="proto",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="unknown",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="false",format="zipkin",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="jaeger",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="proto",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="unknown",sampler_type="unknown",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="const",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="const",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="const",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="lowerbound",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="lowerbound",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="lowerbound",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="probabilistic",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="probabilistic",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="probabilistic",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="ratelimiting",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="ratelimiting",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="ratelimiting",svc="other-services",transport="unknown"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="unknown",svc="other-services",transport="grpc"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="unknown",svc="other-services",transport="http"} 0
jaeger_collector_traces_rejected_total{debug="true",format="zipkin",sampler_type="unknown",svc="other-services",transport="unknown"} 0
## HELP jaeger_collector_traces_saved_by_svc_total saved-by-svc
## TYPE jaeger_collector_traces_saved_by_svc_total counter
jaeger_collector_traces_saved_by_svc_total{debug="false",result="err",sampler_type="const",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="false",result="err",sampler_type="lowerbound",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="false",result="err",sampler_type="probabilistic",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="false",result="err",sampler_type="ratelimiting",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="false",result="err",sampler_type="unknown",svc="frontend"} 1
jaeger_collector_traces_saved_by_svc_total{debug="false",result="err",sampler_type="unknown",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="false",result="ok",sampler_type="const",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="false",result="ok",sampler_type="lowerbound",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="false",result="ok",sampler_type="probabilistic",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="false",result="ok",sampler_type="ratelimiting",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="false",result="ok",sampler_type="unknown",svc="frontend"} 539
jaeger_collector_traces_saved_by_svc_total{debug="false",result="ok",sampler_type="unknown",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="true",result="err",sampler_type="const",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="true",result="err",sampler_type="lowerbound",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="true",result="err",sampler_type="probabilistic",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="true",result="err",sampler_type="ratelimiting",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="true",result="err",sampler_type="unknown",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="true",result="ok",sampler_type="const",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="true",result="ok",sampler_type="lowerbound",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="true",result="ok",sampler_type="probabilistic",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="true",result="ok",sampler_type="ratelimiting",svc="other-services"} 0
jaeger_collector_traces_saved_by_svc_total{debug="true",result="ok",sampler_type="unknown",svc="other-services"} 0
## HELP jaeger_internal_downsampling_ratio downsampling.ratio
## TYPE jaeger_internal_downsampling_ratio gauge
jaeger_internal_downsampling_ratio 1
## HELP jaeger_internal_span_storage_type_cassandra span-storage-type-cassandra
## TYPE jaeger_internal_span_storage_type_cassandra gauge
jaeger_internal_span_storage_type_cassandra 1
## HELP process_cpu_seconds_total Total user and system CPU time spent in seconds.
## TYPE process_cpu_seconds_total counter
process_cpu_seconds_total 7.61
## HELP process_max_fds Maximum number of open file descriptors.
## TYPE process_max_fds gauge
process_max_fds 1.048576e+06
## HELP process_open_fds Number of open file descriptors.
## TYPE process_open_fds gauge
process_open_fds 26
## HELP process_resident_memory_bytes Resident memory size in bytes.
## TYPE process_resident_memory_bytes gauge
process_resident_memory_bytes 2.52928e+07
## HELP process_start_time_seconds Start time of the process since unix epoch in seconds.
## TYPE process_start_time_seconds gauge
process_start_time_seconds 1.69201479512e+09
## HELP process_virtual_memory_bytes Virtual memory size in bytes.
## TYPE process_virtual_memory_bytes gauge
process_virtual_memory_bytes 7.63445248e+08
## HELP process_virtual_memory_max_bytes Maximum amount of virtual memory available in bytes.
## TYPE process_virtual_memory_max_bytes gauge
process_virtual_memory_max_bytes 1.8446744073709552e+19
```
<!-- markdownlint-enable line-length -->

</details>

### Query

<details>
  <summary>Query metrics</summary>

<!-- markdownlint-disable line-length -->
```prometheus
## HELP go_gc_duration_seconds A summary of the pause duration of garbage collection cycles.
## TYPE go_gc_duration_seconds summary
go_gc_duration_seconds{quantile="0"} 2.9114e-05
go_gc_duration_seconds{quantile="0.25"} 7.3604e-05
go_gc_duration_seconds{quantile="0.5"} 9.1003e-05
go_gc_duration_seconds{quantile="0.75"} 0.000113846
go_gc_duration_seconds{quantile="1"} 0.000175166
go_gc_duration_seconds_sum 0.002503905
go_gc_duration_seconds_count 27
## HELP go_goroutines Number of goroutines that currently exist.
## TYPE go_goroutines gauge
go_goroutines 55
## HELP go_info Information about the Go environment.
## TYPE go_info gauge
go_info{version="go1.20.5"} 1
## HELP go_memstats_alloc_bytes Number of bytes allocated and still in use.
## TYPE go_memstats_alloc_bytes gauge
go_memstats_alloc_bytes 3.470208e+06
## HELP go_memstats_alloc_bytes_total Total number of bytes allocated, even if freed.
## TYPE go_memstats_alloc_bytes_total counter
go_memstats_alloc_bytes_total 4.25048e+07
## HELP go_memstats_buck_hash_sys_bytes Number of bytes used by the profiling bucket hash table.
## TYPE go_memstats_buck_hash_sys_bytes gauge
go_memstats_buck_hash_sys_bytes 1.461647e+06
## HELP go_memstats_frees_total Total number of frees.
## TYPE go_memstats_frees_total counter
go_memstats_frees_total 480897
## HELP go_memstats_gc_sys_bytes Number of bytes used for garbage collection system metadata.
## TYPE go_memstats_gc_sys_bytes gauge
go_memstats_gc_sys_bytes 8.593376e+06
## HELP go_memstats_heap_alloc_bytes Number of heap bytes allocated and still in use.
## TYPE go_memstats_heap_alloc_bytes gauge
go_memstats_heap_alloc_bytes 3.470208e+06
## HELP go_memstats_heap_idle_bytes Number of heap bytes waiting to be used.
## TYPE go_memstats_heap_idle_bytes gauge
go_memstats_heap_idle_bytes 2.277376e+06
## HELP go_memstats_heap_inuse_bytes Number of heap bytes that are in use.
## TYPE go_memstats_heap_inuse_bytes gauge
go_memstats_heap_inuse_bytes 4.898816e+06
## HELP go_memstats_heap_objects Number of allocated objects.
## TYPE go_memstats_heap_objects gauge
go_memstats_heap_objects 17956
## HELP go_memstats_heap_released_bytes Number of heap bytes released to OS.
## TYPE go_memstats_heap_released_bytes gauge
go_memstats_heap_released_bytes 1.572864e+06
## HELP go_memstats_heap_sys_bytes Number of heap bytes obtained from system.
## TYPE go_memstats_heap_sys_bytes gauge
go_memstats_heap_sys_bytes 7.176192e+06
## HELP go_memstats_last_gc_time_seconds Number of seconds since 1970 of last garbage collection.
## TYPE go_memstats_last_gc_time_seconds gauge
go_memstats_last_gc_time_seconds 1.6920175691250587e+09
## HELP go_memstats_lookups_total Total number of pointer lookups.
## TYPE go_memstats_lookups_total counter
go_memstats_lookups_total 0
## HELP go_memstats_mallocs_total Total number of mallocs.
## TYPE go_memstats_mallocs_total counter
go_memstats_mallocs_total 498853
## HELP go_memstats_mcache_inuse_bytes Number of bytes in use by mcache structures.
## TYPE go_memstats_mcache_inuse_bytes gauge
go_memstats_mcache_inuse_bytes 1200
## HELP go_memstats_mcache_sys_bytes Number of bytes used for mcache structures obtained from system.
## TYPE go_memstats_mcache_sys_bytes gauge
go_memstats_mcache_sys_bytes 15600
## HELP go_memstats_mspan_inuse_bytes Number of bytes in use by mspan structures.
## TYPE go_memstats_mspan_inuse_bytes gauge
go_memstats_mspan_inuse_bytes 75680
## HELP go_memstats_mspan_sys_bytes Number of bytes used for mspan structures obtained from system.
## TYPE go_memstats_mspan_sys_bytes gauge
go_memstats_mspan_sys_bytes 81600
## HELP go_memstats_next_gc_bytes Number of heap bytes when next garbage collection will take place.
## TYPE go_memstats_next_gc_bytes gauge
go_memstats_next_gc_bytes 6.474992e+06
## HELP go_memstats_other_sys_bytes Number of bytes used for other system allocations.
## TYPE go_memstats_other_sys_bytes gauge
go_memstats_other_sys_bytes 986089
## HELP go_memstats_stack_inuse_bytes Number of bytes in use by the stack allocator.
## TYPE go_memstats_stack_inuse_bytes gauge
go_memstats_stack_inuse_bytes 1.212416e+06
## HELP go_memstats_stack_sys_bytes Number of bytes obtained from system for stack allocator.
## TYPE go_memstats_stack_sys_bytes gauge
go_memstats_stack_sys_bytes 1.212416e+06
## HELP go_memstats_sys_bytes Number of bytes obtained from system.
## TYPE go_memstats_sys_bytes gauge
go_memstats_sys_bytes 1.952692e+07
## HELP go_threads Number of OS threads created.
## TYPE go_threads gauge
go_threads 7
## HELP jaeger_cassandra_attempts_total attempts
## TYPE jaeger_cassandra_attempts_total counter
jaeger_cassandra_attempts_total{table="dependencies"} 0
jaeger_cassandra_attempts_total{table="operation_names"} 0
jaeger_cassandra_attempts_total{table="service_names"} 0
## HELP jaeger_cassandra_errors_total errors
## TYPE jaeger_cassandra_errors_total counter
jaeger_cassandra_errors_total{table="dependencies"} 0
jaeger_cassandra_errors_total{table="operation_names"} 0
jaeger_cassandra_errors_total{table="service_names"} 0
## HELP jaeger_cassandra_inserts_total inserts
## TYPE jaeger_cassandra_inserts_total counter
jaeger_cassandra_inserts_total{table="dependencies"} 0
jaeger_cassandra_inserts_total{table="operation_names"} 0
jaeger_cassandra_inserts_total{table="service_names"} 0
## HELP jaeger_cassandra_latency_err latency-err
## TYPE jaeger_cassandra_latency_err histogram
jaeger_cassandra_latency_err_bucket{table="dependencies",le="0.005"} 0
jaeger_cassandra_latency_err_bucket{table="dependencies",le="0.01"} 0
jaeger_cassandra_latency_err_bucket{table="dependencies",le="0.025"} 0
jaeger_cassandra_latency_err_bucket{table="dependencies",le="0.05"} 0
jaeger_cassandra_latency_err_bucket{table="dependencies",le="0.1"} 0
jaeger_cassandra_latency_err_bucket{table="dependencies",le="0.25"} 0
jaeger_cassandra_latency_err_bucket{table="dependencies",le="0.5"} 0
jaeger_cassandra_latency_err_bucket{table="dependencies",le="1"} 0
jaeger_cassandra_latency_err_bucket{table="dependencies",le="2.5"} 0
jaeger_cassandra_latency_err_bucket{table="dependencies",le="5"} 0
jaeger_cassandra_latency_err_bucket{table="dependencies",le="10"} 0
jaeger_cassandra_latency_err_bucket{table="dependencies",le="+Inf"} 0
jaeger_cassandra_latency_err_sum{table="dependencies"} 0
jaeger_cassandra_latency_err_count{table="dependencies"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.005"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.01"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.025"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.05"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.1"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.25"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="0.5"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="1"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="2.5"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="5"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="10"} 0
jaeger_cassandra_latency_err_bucket{table="operation_names",le="+Inf"} 0
jaeger_cassandra_latency_err_sum{table="operation_names"} 0
jaeger_cassandra_latency_err_count{table="operation_names"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.005"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.01"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.025"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.05"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.1"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.25"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="0.5"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="1"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="2.5"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="5"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="10"} 0
jaeger_cassandra_latency_err_bucket{table="service_names",le="+Inf"} 0
jaeger_cassandra_latency_err_sum{table="service_names"} 0
jaeger_cassandra_latency_err_count{table="service_names"} 0
## HELP jaeger_cassandra_latency_ok latency-ok
## TYPE jaeger_cassandra_latency_ok histogram
jaeger_cassandra_latency_ok_bucket{table="dependencies",le="0.005"} 0
jaeger_cassandra_latency_ok_bucket{table="dependencies",le="0.01"} 0
jaeger_cassandra_latency_ok_bucket{table="dependencies",le="0.025"} 0
jaeger_cassandra_latency_ok_bucket{table="dependencies",le="0.05"} 0
jaeger_cassandra_latency_ok_bucket{table="dependencies",le="0.1"} 0
jaeger_cassandra_latency_ok_bucket{table="dependencies",le="0.25"} 0
jaeger_cassandra_latency_ok_bucket{table="dependencies",le="0.5"} 0
jaeger_cassandra_latency_ok_bucket{table="dependencies",le="1"} 0
jaeger_cassandra_latency_ok_bucket{table="dependencies",le="2.5"} 0
jaeger_cassandra_latency_ok_bucket{table="dependencies",le="5"} 0
jaeger_cassandra_latency_ok_bucket{table="dependencies",le="10"} 0
jaeger_cassandra_latency_ok_bucket{table="dependencies",le="+Inf"} 0
jaeger_cassandra_latency_ok_sum{table="dependencies"} 0
jaeger_cassandra_latency_ok_count{table="dependencies"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.005"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.01"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.025"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.05"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.1"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.25"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="0.5"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="1"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="2.5"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="5"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="10"} 0
jaeger_cassandra_latency_ok_bucket{table="operation_names",le="+Inf"} 0
jaeger_cassandra_latency_ok_sum{table="operation_names"} 0
jaeger_cassandra_latency_ok_count{table="operation_names"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.005"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.01"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.025"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.05"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.1"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.25"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="0.5"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="1"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="2.5"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="5"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="10"} 0
jaeger_cassandra_latency_ok_bucket{table="service_names",le="+Inf"} 0
jaeger_cassandra_latency_ok_sum{table="service_names"} 0
jaeger_cassandra_latency_ok_count{table="service_names"} 0
## HELP jaeger_cassandra_read_attempts_total attempts
## TYPE jaeger_cassandra_read_attempts_total counter
jaeger_cassandra_read_attempts_total{table="duration_index"} 0
jaeger_cassandra_read_attempts_total{table="query_traces"} 0
jaeger_cassandra_read_attempts_total{table="read_traces"} 0
jaeger_cassandra_read_attempts_total{table="service_name_index"} 0
jaeger_cassandra_read_attempts_total{table="service_operation_index"} 0
jaeger_cassandra_read_attempts_total{table="tag_index"} 0
## HELP jaeger_cassandra_read_errors_total errors
## TYPE jaeger_cassandra_read_errors_total counter
jaeger_cassandra_read_errors_total{table="duration_index"} 0
jaeger_cassandra_read_errors_total{table="query_traces"} 0
jaeger_cassandra_read_errors_total{table="read_traces"} 0
jaeger_cassandra_read_errors_total{table="service_name_index"} 0
jaeger_cassandra_read_errors_total{table="service_operation_index"} 0
jaeger_cassandra_read_errors_total{table="tag_index"} 0
## HELP jaeger_cassandra_read_inserts_total inserts
## TYPE jaeger_cassandra_read_inserts_total counter
jaeger_cassandra_read_inserts_total{table="duration_index"} 0
jaeger_cassandra_read_inserts_total{table="query_traces"} 0
jaeger_cassandra_read_inserts_total{table="read_traces"} 0
jaeger_cassandra_read_inserts_total{table="service_name_index"} 0
jaeger_cassandra_read_inserts_total{table="service_operation_index"} 0
jaeger_cassandra_read_inserts_total{table="tag_index"} 0
## HELP jaeger_cassandra_read_latency_err latency-err
## TYPE jaeger_cassandra_read_latency_err histogram
jaeger_cassandra_read_latency_err_bucket{table="duration_index",le="0.005"} 0
jaeger_cassandra_read_latency_err_bucket{table="duration_index",le="0.01"} 0
jaeger_cassandra_read_latency_err_bucket{table="duration_index",le="0.025"} 0
jaeger_cassandra_read_latency_err_bucket{table="duration_index",le="0.05"} 0
jaeger_cassandra_read_latency_err_bucket{table="duration_index",le="0.1"} 0
jaeger_cassandra_read_latency_err_bucket{table="duration_index",le="0.25"} 0
jaeger_cassandra_read_latency_err_bucket{table="duration_index",le="0.5"} 0
jaeger_cassandra_read_latency_err_bucket{table="duration_index",le="1"} 0
jaeger_cassandra_read_latency_err_bucket{table="duration_index",le="2.5"} 0
jaeger_cassandra_read_latency_err_bucket{table="duration_index",le="5"} 0
jaeger_cassandra_read_latency_err_bucket{table="duration_index",le="10"} 0
jaeger_cassandra_read_latency_err_bucket{table="duration_index",le="+Inf"} 0
jaeger_cassandra_read_latency_err_sum{table="duration_index"} 0
jaeger_cassandra_read_latency_err_count{table="duration_index"} 0
jaeger_cassandra_read_latency_err_bucket{table="query_traces",le="0.005"} 0
jaeger_cassandra_read_latency_err_bucket{table="query_traces",le="0.01"} 0
jaeger_cassandra_read_latency_err_bucket{table="query_traces",le="0.025"} 0
jaeger_cassandra_read_latency_err_bucket{table="query_traces",le="0.05"} 0
jaeger_cassandra_read_latency_err_bucket{table="query_traces",le="0.1"} 0
jaeger_cassandra_read_latency_err_bucket{table="query_traces",le="0.25"} 0
jaeger_cassandra_read_latency_err_bucket{table="query_traces",le="0.5"} 0
jaeger_cassandra_read_latency_err_bucket{table="query_traces",le="1"} 0
jaeger_cassandra_read_latency_err_bucket{table="query_traces",le="2.5"} 0
jaeger_cassandra_read_latency_err_bucket{table="query_traces",le="5"} 0
jaeger_cassandra_read_latency_err_bucket{table="query_traces",le="10"} 0
jaeger_cassandra_read_latency_err_bucket{table="query_traces",le="+Inf"} 0
jaeger_cassandra_read_latency_err_sum{table="query_traces"} 0
jaeger_cassandra_read_latency_err_count{table="query_traces"} 0
jaeger_cassandra_read_latency_err_bucket{table="read_traces",le="0.005"} 0
jaeger_cassandra_read_latency_err_bucket{table="read_traces",le="0.01"} 0
jaeger_cassandra_read_latency_err_bucket{table="read_traces",le="0.025"} 0
jaeger_cassandra_read_latency_err_bucket{table="read_traces",le="0.05"} 0
jaeger_cassandra_read_latency_err_bucket{table="read_traces",le="0.1"} 0
jaeger_cassandra_read_latency_err_bucket{table="read_traces",le="0.25"} 0
jaeger_cassandra_read_latency_err_bucket{table="read_traces",le="0.5"} 0
jaeger_cassandra_read_latency_err_bucket{table="read_traces",le="1"} 0
jaeger_cassandra_read_latency_err_bucket{table="read_traces",le="2.5"} 0
jaeger_cassandra_read_latency_err_bucket{table="read_traces",le="5"} 0
jaeger_cassandra_read_latency_err_bucket{table="read_traces",le="10"} 0
jaeger_cassandra_read_latency_err_bucket{table="read_traces",le="+Inf"} 0
jaeger_cassandra_read_latency_err_sum{table="read_traces"} 0
jaeger_cassandra_read_latency_err_count{table="read_traces"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_name_index",le="0.005"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_name_index",le="0.01"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_name_index",le="0.025"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_name_index",le="0.05"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_name_index",le="0.1"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_name_index",le="0.25"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_name_index",le="0.5"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_name_index",le="1"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_name_index",le="2.5"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_name_index",le="5"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_name_index",le="10"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_name_index",le="+Inf"} 0
jaeger_cassandra_read_latency_err_sum{table="service_name_index"} 0
jaeger_cassandra_read_latency_err_count{table="service_name_index"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_operation_index",le="0.005"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_operation_index",le="0.01"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_operation_index",le="0.025"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_operation_index",le="0.05"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_operation_index",le="0.1"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_operation_index",le="0.25"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_operation_index",le="0.5"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_operation_index",le="1"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_operation_index",le="2.5"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_operation_index",le="5"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_operation_index",le="10"} 0
jaeger_cassandra_read_latency_err_bucket{table="service_operation_index",le="+Inf"} 0
jaeger_cassandra_read_latency_err_sum{table="service_operation_index"} 0
jaeger_cassandra_read_latency_err_count{table="service_operation_index"} 0
jaeger_cassandra_read_latency_err_bucket{table="tag_index",le="0.005"} 0
jaeger_cassandra_read_latency_err_bucket{table="tag_index",le="0.01"} 0
jaeger_cassandra_read_latency_err_bucket{table="tag_index",le="0.025"} 0
jaeger_cassandra_read_latency_err_bucket{table="tag_index",le="0.05"} 0
jaeger_cassandra_read_latency_err_bucket{table="tag_index",le="0.1"} 0
jaeger_cassandra_read_latency_err_bucket{table="tag_index",le="0.25"} 0
jaeger_cassandra_read_latency_err_bucket{table="tag_index",le="0.5"} 0
jaeger_cassandra_read_latency_err_bucket{table="tag_index",le="1"} 0
jaeger_cassandra_read_latency_err_bucket{table="tag_index",le="2.5"} 0
jaeger_cassandra_read_latency_err_bucket{table="tag_index",le="5"} 0
jaeger_cassandra_read_latency_err_bucket{table="tag_index",le="10"} 0
jaeger_cassandra_read_latency_err_bucket{table="tag_index",le="+Inf"} 0
jaeger_cassandra_read_latency_err_sum{table="tag_index"} 0
jaeger_cassandra_read_latency_err_count{table="tag_index"} 0
## HELP jaeger_cassandra_read_latency_ok latency-ok
## TYPE jaeger_cassandra_read_latency_ok histogram
jaeger_cassandra_read_latency_ok_bucket{table="duration_index",le="0.005"} 0
jaeger_cassandra_read_latency_ok_bucket{table="duration_index",le="0.01"} 0
jaeger_cassandra_read_latency_ok_bucket{table="duration_index",le="0.025"} 0
jaeger_cassandra_read_latency_ok_bucket{table="duration_index",le="0.05"} 0
jaeger_cassandra_read_latency_ok_bucket{table="duration_index",le="0.1"} 0
jaeger_cassandra_read_latency_ok_bucket{table="duration_index",le="0.25"} 0
jaeger_cassandra_read_latency_ok_bucket{table="duration_index",le="0.5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="duration_index",le="1"} 0
jaeger_cassandra_read_latency_ok_bucket{table="duration_index",le="2.5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="duration_index",le="5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="duration_index",le="10"} 0
jaeger_cassandra_read_latency_ok_bucket{table="duration_index",le="+Inf"} 0
jaeger_cassandra_read_latency_ok_sum{table="duration_index"} 0
jaeger_cassandra_read_latency_ok_count{table="duration_index"} 0
jaeger_cassandra_read_latency_ok_bucket{table="query_traces",le="0.005"} 0
jaeger_cassandra_read_latency_ok_bucket{table="query_traces",le="0.01"} 0
jaeger_cassandra_read_latency_ok_bucket{table="query_traces",le="0.025"} 0
jaeger_cassandra_read_latency_ok_bucket{table="query_traces",le="0.05"} 0
jaeger_cassandra_read_latency_ok_bucket{table="query_traces",le="0.1"} 0
jaeger_cassandra_read_latency_ok_bucket{table="query_traces",le="0.25"} 0
jaeger_cassandra_read_latency_ok_bucket{table="query_traces",le="0.5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="query_traces",le="1"} 0
jaeger_cassandra_read_latency_ok_bucket{table="query_traces",le="2.5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="query_traces",le="5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="query_traces",le="10"} 0
jaeger_cassandra_read_latency_ok_bucket{table="query_traces",le="+Inf"} 0
jaeger_cassandra_read_latency_ok_sum{table="query_traces"} 0
jaeger_cassandra_read_latency_ok_count{table="query_traces"} 0
jaeger_cassandra_read_latency_ok_bucket{table="read_traces",le="0.005"} 0
jaeger_cassandra_read_latency_ok_bucket{table="read_traces",le="0.01"} 0
jaeger_cassandra_read_latency_ok_bucket{table="read_traces",le="0.025"} 0
jaeger_cassandra_read_latency_ok_bucket{table="read_traces",le="0.05"} 0
jaeger_cassandra_read_latency_ok_bucket{table="read_traces",le="0.1"} 0
jaeger_cassandra_read_latency_ok_bucket{table="read_traces",le="0.25"} 0
jaeger_cassandra_read_latency_ok_bucket{table="read_traces",le="0.5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="read_traces",le="1"} 0
jaeger_cassandra_read_latency_ok_bucket{table="read_traces",le="2.5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="read_traces",le="5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="read_traces",le="10"} 0
jaeger_cassandra_read_latency_ok_bucket{table="read_traces",le="+Inf"} 0
jaeger_cassandra_read_latency_ok_sum{table="read_traces"} 0
jaeger_cassandra_read_latency_ok_count{table="read_traces"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_name_index",le="0.005"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_name_index",le="0.01"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_name_index",le="0.025"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_name_index",le="0.05"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_name_index",le="0.1"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_name_index",le="0.25"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_name_index",le="0.5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_name_index",le="1"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_name_index",le="2.5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_name_index",le="5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_name_index",le="10"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_name_index",le="+Inf"} 0
jaeger_cassandra_read_latency_ok_sum{table="service_name_index"} 0
jaeger_cassandra_read_latency_ok_count{table="service_name_index"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_operation_index",le="0.005"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_operation_index",le="0.01"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_operation_index",le="0.025"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_operation_index",le="0.05"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_operation_index",le="0.1"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_operation_index",le="0.25"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_operation_index",le="0.5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_operation_index",le="1"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_operation_index",le="2.5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_operation_index",le="5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_operation_index",le="10"} 0
jaeger_cassandra_read_latency_ok_bucket{table="service_operation_index",le="+Inf"} 0
jaeger_cassandra_read_latency_ok_sum{table="service_operation_index"} 0
jaeger_cassandra_read_latency_ok_count{table="service_operation_index"} 0
jaeger_cassandra_read_latency_ok_bucket{table="tag_index",le="0.005"} 0
jaeger_cassandra_read_latency_ok_bucket{table="tag_index",le="0.01"} 0
jaeger_cassandra_read_latency_ok_bucket{table="tag_index",le="0.025"} 0
jaeger_cassandra_read_latency_ok_bucket{table="tag_index",le="0.05"} 0
jaeger_cassandra_read_latency_ok_bucket{table="tag_index",le="0.1"} 0
jaeger_cassandra_read_latency_ok_bucket{table="tag_index",le="0.25"} 0
jaeger_cassandra_read_latency_ok_bucket{table="tag_index",le="0.5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="tag_index",le="1"} 0
jaeger_cassandra_read_latency_ok_bucket{table="tag_index",le="2.5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="tag_index",le="5"} 0
jaeger_cassandra_read_latency_ok_bucket{table="tag_index",le="10"} 0
jaeger_cassandra_read_latency_ok_bucket{table="tag_index",le="+Inf"} 0
jaeger_cassandra_read_latency_ok_sum{table="tag_index"} 0
jaeger_cassandra_read_latency_ok_count{table="tag_index"} 0
## HELP jaeger_internal_downsampling_ratio downsampling.ratio
## TYPE jaeger_internal_downsampling_ratio gauge
jaeger_internal_downsampling_ratio 1
## HELP jaeger_internal_span_storage_type_cassandra span-storage-type-cassandra
## TYPE jaeger_internal_span_storage_type_cassandra gauge
jaeger_internal_span_storage_type_cassandra 1
## HELP jaeger_query_build_info build_info
## TYPE jaeger_query_build_info gauge
jaeger_query_build_info{build_date="2023-07-06T20:38:11Z",revision="ee6cc41ef62ba8f04de8a16431b43b620bdf571c",version="v1.62.0"} 1
## HELP jaeger_query_latency latency
## TYPE jaeger_query_latency histogram
jaeger_query_latency_bucket{operation="find_trace_ids",result="err",le="0.005"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="err",le="0.01"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="err",le="0.025"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="err",le="0.05"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="err",le="0.1"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="err",le="0.25"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="err",le="0.5"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="err",le="1"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="err",le="2.5"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="err",le="5"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="err",le="10"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="err",le="+Inf"} 0
jaeger_query_latency_sum{operation="find_trace_ids",result="err"} 0
jaeger_query_latency_count{operation="find_trace_ids",result="err"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="ok",le="0.005"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="ok",le="0.01"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="ok",le="0.025"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="ok",le="0.05"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="ok",le="0.1"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="ok",le="0.25"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="ok",le="0.5"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="ok",le="1"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="ok",le="2.5"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="ok",le="5"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="ok",le="10"} 0
jaeger_query_latency_bucket{operation="find_trace_ids",result="ok",le="+Inf"} 0
jaeger_query_latency_sum{operation="find_trace_ids",result="ok"} 0
jaeger_query_latency_count{operation="find_trace_ids",result="ok"} 0
jaeger_query_latency_bucket{operation="find_traces",result="err",le="0.005"} 0
jaeger_query_latency_bucket{operation="find_traces",result="err",le="0.01"} 0
jaeger_query_latency_bucket{operation="find_traces",result="err",le="0.025"} 0
jaeger_query_latency_bucket{operation="find_traces",result="err",le="0.05"} 0
jaeger_query_latency_bucket{operation="find_traces",result="err",le="0.1"} 0
jaeger_query_latency_bucket{operation="find_traces",result="err",le="0.25"} 0
jaeger_query_latency_bucket{operation="find_traces",result="err",le="0.5"} 0
jaeger_query_latency_bucket{operation="find_traces",result="err",le="1"} 0
jaeger_query_latency_bucket{operation="find_traces",result="err",le="2.5"} 0
jaeger_query_latency_bucket{operation="find_traces",result="err",le="5"} 0
jaeger_query_latency_bucket{operation="find_traces",result="err",le="10"} 0
jaeger_query_latency_bucket{operation="find_traces",result="err",le="+Inf"} 0
jaeger_query_latency_sum{operation="find_traces",result="err"} 0
jaeger_query_latency_count{operation="find_traces",result="err"} 0
jaeger_query_latency_bucket{operation="find_traces",result="ok",le="0.005"} 0
jaeger_query_latency_bucket{operation="find_traces",result="ok",le="0.01"} 0
jaeger_query_latency_bucket{operation="find_traces",result="ok",le="0.025"} 0
jaeger_query_latency_bucket{operation="find_traces",result="ok",le="0.05"} 0
jaeger_query_latency_bucket{operation="find_traces",result="ok",le="0.1"} 0
jaeger_query_latency_bucket{operation="find_traces",result="ok",le="0.25"} 0
jaeger_query_latency_bucket{operation="find_traces",result="ok",le="0.5"} 0
jaeger_query_latency_bucket{operation="find_traces",result="ok",le="1"} 0
jaeger_query_latency_bucket{operation="find_traces",result="ok",le="2.5"} 0
jaeger_query_latency_bucket{operation="find_traces",result="ok",le="5"} 0
jaeger_query_latency_bucket{operation="find_traces",result="ok",le="10"} 0
jaeger_query_latency_bucket{operation="find_traces",result="ok",le="+Inf"} 0
jaeger_query_latency_sum{operation="find_traces",result="ok"} 0
jaeger_query_latency_count{operation="find_traces",result="ok"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="err",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="err",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="err",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="err",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="err",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="err",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="err",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="err",le="1"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="err",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="err",le="5"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="err",le="10"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="err",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_call_rates",result="err"} 0
jaeger_query_latency_count{operation="get_call_rates",result="err"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="ok",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="ok",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="ok",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="ok",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="ok",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="ok",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="ok",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="ok",le="1"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="ok",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="ok",le="5"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="ok",le="10"} 0
jaeger_query_latency_bucket{operation="get_call_rates",result="ok",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_call_rates",result="ok"} 0
jaeger_query_latency_count{operation="get_call_rates",result="ok"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="err",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="err",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="err",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="err",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="err",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="err",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="err",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="err",le="1"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="err",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="err",le="5"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="err",le="10"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="err",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_error_rates",result="err"} 0
jaeger_query_latency_count{operation="get_error_rates",result="err"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="ok",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="ok",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="ok",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="ok",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="ok",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="ok",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="ok",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="ok",le="1"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="ok",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="ok",le="5"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="ok",le="10"} 0
jaeger_query_latency_bucket{operation="get_error_rates",result="ok",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_error_rates",result="ok"} 0
jaeger_query_latency_count{operation="get_error_rates",result="ok"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="err",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="err",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="err",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="err",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="err",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="err",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="err",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="err",le="1"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="err",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="err",le="5"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="err",le="10"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="err",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_latencies",result="err"} 0
jaeger_query_latency_count{operation="get_latencies",result="err"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="ok",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="ok",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="ok",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="ok",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="ok",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="ok",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="ok",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="ok",le="1"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="ok",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="ok",le="5"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="ok",le="10"} 0
jaeger_query_latency_bucket{operation="get_latencies",result="ok",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_latencies",result="ok"} 0
jaeger_query_latency_count{operation="get_latencies",result="ok"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="err",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="err",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="err",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="err",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="err",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="err",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="err",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="err",le="1"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="err",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="err",le="5"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="err",le="10"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="err",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_min_step_duration",result="err"} 0
jaeger_query_latency_count{operation="get_min_step_duration",result="err"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="ok",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="ok",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="ok",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="ok",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="ok",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="ok",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="ok",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="ok",le="1"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="ok",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="ok",le="5"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="ok",le="10"} 0
jaeger_query_latency_bucket{operation="get_min_step_duration",result="ok",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_min_step_duration",result="ok"} 0
jaeger_query_latency_count{operation="get_min_step_duration",result="ok"} 0
jaeger_query_latency_bucket{operation="get_operations",result="err",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_operations",result="err",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_operations",result="err",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_operations",result="err",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_operations",result="err",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_operations",result="err",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_operations",result="err",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_operations",result="err",le="1"} 0
jaeger_query_latency_bucket{operation="get_operations",result="err",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_operations",result="err",le="5"} 0
jaeger_query_latency_bucket{operation="get_operations",result="err",le="10"} 0
jaeger_query_latency_bucket{operation="get_operations",result="err",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_operations",result="err"} 0
jaeger_query_latency_count{operation="get_operations",result="err"} 0
jaeger_query_latency_bucket{operation="get_operations",result="ok",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_operations",result="ok",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_operations",result="ok",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_operations",result="ok",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_operations",result="ok",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_operations",result="ok",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_operations",result="ok",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_operations",result="ok",le="1"} 0
jaeger_query_latency_bucket{operation="get_operations",result="ok",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_operations",result="ok",le="5"} 0
jaeger_query_latency_bucket{operation="get_operations",result="ok",le="10"} 0
jaeger_query_latency_bucket{operation="get_operations",result="ok",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_operations",result="ok"} 0
jaeger_query_latency_count{operation="get_operations",result="ok"} 0
jaeger_query_latency_bucket{operation="get_services",result="err",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_services",result="err",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_services",result="err",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_services",result="err",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_services",result="err",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_services",result="err",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_services",result="err",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_services",result="err",le="1"} 0
jaeger_query_latency_bucket{operation="get_services",result="err",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_services",result="err",le="5"} 0
jaeger_query_latency_bucket{operation="get_services",result="err",le="10"} 0
jaeger_query_latency_bucket{operation="get_services",result="err",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_services",result="err"} 0
jaeger_query_latency_count{operation="get_services",result="err"} 0
jaeger_query_latency_bucket{operation="get_services",result="ok",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_services",result="ok",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_services",result="ok",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_services",result="ok",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_services",result="ok",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_services",result="ok",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_services",result="ok",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_services",result="ok",le="1"} 0
jaeger_query_latency_bucket{operation="get_services",result="ok",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_services",result="ok",le="5"} 0
jaeger_query_latency_bucket{operation="get_services",result="ok",le="10"} 0
jaeger_query_latency_bucket{operation="get_services",result="ok",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_services",result="ok"} 0
jaeger_query_latency_count{operation="get_services",result="ok"} 0
jaeger_query_latency_bucket{operation="get_trace",result="err",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_trace",result="err",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_trace",result="err",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_trace",result="err",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_trace",result="err",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_trace",result="err",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_trace",result="err",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_trace",result="err",le="1"} 0
jaeger_query_latency_bucket{operation="get_trace",result="err",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_trace",result="err",le="5"} 0
jaeger_query_latency_bucket{operation="get_trace",result="err",le="10"} 0
jaeger_query_latency_bucket{operation="get_trace",result="err",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_trace",result="err"} 0
jaeger_query_latency_count{operation="get_trace",result="err"} 0
jaeger_query_latency_bucket{operation="get_trace",result="ok",le="0.005"} 0
jaeger_query_latency_bucket{operation="get_trace",result="ok",le="0.01"} 0
jaeger_query_latency_bucket{operation="get_trace",result="ok",le="0.025"} 0
jaeger_query_latency_bucket{operation="get_trace",result="ok",le="0.05"} 0
jaeger_query_latency_bucket{operation="get_trace",result="ok",le="0.1"} 0
jaeger_query_latency_bucket{operation="get_trace",result="ok",le="0.25"} 0
jaeger_query_latency_bucket{operation="get_trace",result="ok",le="0.5"} 0
jaeger_query_latency_bucket{operation="get_trace",result="ok",le="1"} 0
jaeger_query_latency_bucket{operation="get_trace",result="ok",le="2.5"} 0
jaeger_query_latency_bucket{operation="get_trace",result="ok",le="5"} 0
jaeger_query_latency_bucket{operation="get_trace",result="ok",le="10"} 0
jaeger_query_latency_bucket{operation="get_trace",result="ok",le="+Inf"} 0
jaeger_query_latency_sum{operation="get_trace",result="ok"} 0
jaeger_query_latency_count{operation="get_trace",result="ok"} 0
## HELP jaeger_query_requests_total requests
## TYPE jaeger_query_requests_total counter
jaeger_query_requests_total{operation="find_trace_ids",result="err"} 0
jaeger_query_requests_total{operation="find_trace_ids",result="ok"} 0
jaeger_query_requests_total{operation="find_traces",result="err"} 0
jaeger_query_requests_total{operation="find_traces",result="ok"} 0
jaeger_query_requests_total{operation="get_call_rates",result="err"} 0
jaeger_query_requests_total{operation="get_call_rates",result="ok"} 0
jaeger_query_requests_total{operation="get_error_rates",result="err"} 0
jaeger_query_requests_total{operation="get_error_rates",result="ok"} 0
jaeger_query_requests_total{operation="get_latencies",result="err"} 0
jaeger_query_requests_total{operation="get_latencies",result="ok"} 0
jaeger_query_requests_total{operation="get_min_step_duration",result="err"} 0
jaeger_query_requests_total{operation="get_min_step_duration",result="ok"} 0
jaeger_query_requests_total{operation="get_operations",result="err"} 0
jaeger_query_requests_total{operation="get_operations",result="ok"} 0
jaeger_query_requests_total{operation="get_services",result="err"} 0
jaeger_query_requests_total{operation="get_services",result="ok"} 0
jaeger_query_requests_total{operation="get_trace",result="err"} 0
jaeger_query_requests_total{operation="get_trace",result="ok"} 0
## HELP jaeger_query_responses responses
## TYPE jaeger_query_responses histogram
jaeger_query_responses_bucket{operation="find_trace_ids",le="0.005"} 0
jaeger_query_responses_bucket{operation="find_trace_ids",le="0.01"} 0
jaeger_query_responses_bucket{operation="find_trace_ids",le="0.025"} 0
jaeger_query_responses_bucket{operation="find_trace_ids",le="0.05"} 0
jaeger_query_responses_bucket{operation="find_trace_ids",le="0.1"} 0
jaeger_query_responses_bucket{operation="find_trace_ids",le="0.25"} 0
jaeger_query_responses_bucket{operation="find_trace_ids",le="0.5"} 0
jaeger_query_responses_bucket{operation="find_trace_ids",le="1"} 0
jaeger_query_responses_bucket{operation="find_trace_ids",le="2.5"} 0
jaeger_query_responses_bucket{operation="find_trace_ids",le="5"} 0
jaeger_query_responses_bucket{operation="find_trace_ids",le="10"} 0
jaeger_query_responses_bucket{operation="find_trace_ids",le="+Inf"} 0
jaeger_query_responses_sum{operation="find_trace_ids"} 0
jaeger_query_responses_count{operation="find_trace_ids"} 0
jaeger_query_responses_bucket{operation="find_traces",le="0.005"} 0
jaeger_query_responses_bucket{operation="find_traces",le="0.01"} 0
jaeger_query_responses_bucket{operation="find_traces",le="0.025"} 0
jaeger_query_responses_bucket{operation="find_traces",le="0.05"} 0
jaeger_query_responses_bucket{operation="find_traces",le="0.1"} 0
jaeger_query_responses_bucket{operation="find_traces",le="0.25"} 0
jaeger_query_responses_bucket{operation="find_traces",le="0.5"} 0
jaeger_query_responses_bucket{operation="find_traces",le="1"} 0
jaeger_query_responses_bucket{operation="find_traces",le="2.5"} 0
jaeger_query_responses_bucket{operation="find_traces",le="5"} 0
jaeger_query_responses_bucket{operation="find_traces",le="10"} 0
jaeger_query_responses_bucket{operation="find_traces",le="+Inf"} 0
jaeger_query_responses_sum{operation="find_traces"} 0
jaeger_query_responses_count{operation="find_traces"} 0
jaeger_query_responses_bucket{operation="get_operations",le="0.005"} 0
jaeger_query_responses_bucket{operation="get_operations",le="0.01"} 0
jaeger_query_responses_bucket{operation="get_operations",le="0.025"} 0
jaeger_query_responses_bucket{operation="get_operations",le="0.05"} 0
jaeger_query_responses_bucket{operation="get_operations",le="0.1"} 0
jaeger_query_responses_bucket{operation="get_operations",le="0.25"} 0
jaeger_query_responses_bucket{operation="get_operations",le="0.5"} 0
jaeger_query_responses_bucket{operation="get_operations",le="1"} 0
jaeger_query_responses_bucket{operation="get_operations",le="2.5"} 0
jaeger_query_responses_bucket{operation="get_operations",le="5"} 0
jaeger_query_responses_bucket{operation="get_operations",le="10"} 0
jaeger_query_responses_bucket{operation="get_operations",le="+Inf"} 0
jaeger_query_responses_sum{operation="get_operations"} 0
jaeger_query_responses_count{operation="get_operations"} 0
jaeger_query_responses_bucket{operation="get_services",le="0.005"} 0
jaeger_query_responses_bucket{operation="get_services",le="0.01"} 0
jaeger_query_responses_bucket{operation="get_services",le="0.025"} 0
jaeger_query_responses_bucket{operation="get_services",le="0.05"} 0
jaeger_query_responses_bucket{operation="get_services",le="0.1"} 0
jaeger_query_responses_bucket{operation="get_services",le="0.25"} 0
jaeger_query_responses_bucket{operation="get_services",le="0.5"} 0
jaeger_query_responses_bucket{operation="get_services",le="1"} 0
jaeger_query_responses_bucket{operation="get_services",le="2.5"} 0
jaeger_query_responses_bucket{operation="get_services",le="5"} 0
jaeger_query_responses_bucket{operation="get_services",le="10"} 0
jaeger_query_responses_bucket{operation="get_services",le="+Inf"} 0
jaeger_query_responses_sum{operation="get_services"} 0
jaeger_query_responses_count{operation="get_services"} 0
jaeger_query_responses_bucket{operation="get_trace",le="0.005"} 0
jaeger_query_responses_bucket{operation="get_trace",le="0.01"} 0
jaeger_query_responses_bucket{operation="get_trace",le="0.025"} 0
jaeger_query_responses_bucket{operation="get_trace",le="0.05"} 0
jaeger_query_responses_bucket{operation="get_trace",le="0.1"} 0
jaeger_query_responses_bucket{operation="get_trace",le="0.25"} 0
jaeger_query_responses_bucket{operation="get_trace",le="0.5"} 0
jaeger_query_responses_bucket{operation="get_trace",le="1"} 0
jaeger_query_responses_bucket{operation="get_trace",le="2.5"} 0
jaeger_query_responses_bucket{operation="get_trace",le="5"} 0
jaeger_query_responses_bucket{operation="get_trace",le="10"} 0
jaeger_query_responses_bucket{operation="get_trace",le="+Inf"} 0
jaeger_query_responses_sum{operation="get_trace"} 0
jaeger_query_responses_count{operation="get_trace"} 0
## HELP jaeger_tracer_baggage_restrictions_updates_total Number of times baggage restrictions were successfully updated
## TYPE jaeger_tracer_baggage_restrictions_updates_total counter
jaeger_tracer_baggage_restrictions_updates_total{result="err"} 0
jaeger_tracer_baggage_restrictions_updates_total{result="ok"} 0
## HELP jaeger_tracer_baggage_truncations_total Number of times baggage was truncated as per baggage restrictions
## TYPE jaeger_tracer_baggage_truncations_total counter
jaeger_tracer_baggage_truncations_total 0
## HELP jaeger_tracer_baggage_updates_total Number of times baggage was successfully written or updated on spans
## TYPE jaeger_tracer_baggage_updates_total counter
jaeger_tracer_baggage_updates_total{result="err"} 0
jaeger_tracer_baggage_updates_total{result="ok"} 0
## HELP jaeger_tracer_finished_spans_total Number of sampled spans finished by this tracer
## TYPE jaeger_tracer_finished_spans_total counter
jaeger_tracer_finished_spans_total{sampled="delayed"} 0
jaeger_tracer_finished_spans_total{sampled="n"} 0
jaeger_tracer_finished_spans_total{sampled="y"} 0
## HELP jaeger_tracer_reporter_queue_length Current number of spans in the reporter queue
## TYPE jaeger_tracer_reporter_queue_length gauge
jaeger_tracer_reporter_queue_length 0
## HELP jaeger_tracer_reporter_spans_total Number of spans successfully reported
## TYPE jaeger_tracer_reporter_spans_total counter
jaeger_tracer_reporter_spans_total{result="dropped"} 0
jaeger_tracer_reporter_spans_total{result="err"} 0
jaeger_tracer_reporter_spans_total{result="ok"} 0
## HELP jaeger_tracer_sampler_queries_total Number of times the Sampler succeeded to retrieve sampling strategy
## TYPE jaeger_tracer_sampler_queries_total counter
jaeger_tracer_sampler_queries_total{result="err"} 0
jaeger_tracer_sampler_queries_total{result="ok"} 0
## HELP jaeger_tracer_sampler_updates_total Number of times the Sampler succeeded to retrieve and update sampling strategy
## TYPE jaeger_tracer_sampler_updates_total counter
jaeger_tracer_sampler_updates_total{result="err"} 0
jaeger_tracer_sampler_updates_total{result="ok"} 0
## HELP jaeger_tracer_span_context_decoding_errors_total Number of errors decoding tracing context
## TYPE jaeger_tracer_span_context_decoding_errors_total counter
jaeger_tracer_span_context_decoding_errors_total 0
## HELP jaeger_tracer_started_spans_total Number of spans started by this tracer as sampled
## TYPE jaeger_tracer_started_spans_total counter
jaeger_tracer_started_spans_total{sampled="delayed"} 0
jaeger_tracer_started_spans_total{sampled="n"} 0
jaeger_tracer_started_spans_total{sampled="y"} 0
## HELP jaeger_tracer_throttled_debug_spans_total Number of times debug spans were throttled
## TYPE jaeger_tracer_throttled_debug_spans_total counter
jaeger_tracer_throttled_debug_spans_total 0
## HELP jaeger_tracer_throttler_updates_total Number of times throttler successfully updated
## TYPE jaeger_tracer_throttler_updates_total counter
jaeger_tracer_throttler_updates_total{result="err"} 0
jaeger_tracer_throttler_updates_total{result="ok"} 0
## HELP jaeger_tracer_traces_total Number of traces started by this tracer as sampled
## TYPE jaeger_tracer_traces_total counter
jaeger_tracer_traces_total{sampled="n",state="joined"} 0
jaeger_tracer_traces_total{sampled="n",state="started"} 0
jaeger_tracer_traces_total{sampled="y",state="joined"} 0
jaeger_tracer_traces_total{sampled="y",state="started"} 0
## HELP process_cpu_seconds_total Total user and system CPU time spent in seconds.
## TYPE process_cpu_seconds_total counter
process_cpu_seconds_total 4.09
## HELP process_max_fds Maximum number of open file descriptors.
## TYPE process_max_fds gauge
process_max_fds 1.048576e+06
## HELP process_open_fds Number of open file descriptors.
## TYPE process_open_fds gauge
process_open_fds 26
## HELP process_resident_memory_bytes Resident memory size in bytes.
## TYPE process_resident_memory_bytes gauge
process_resident_memory_bytes 2.0004864e+07
## HELP process_start_time_seconds Start time of the process since unix epoch in seconds.
## TYPE process_start_time_seconds gauge
process_start_time_seconds 1.69201479849e+09
## HELP process_virtual_memory_bytes Virtual memory size in bytes.
## TYPE process_virtual_memory_bytes gauge
process_virtual_memory_bytes 7.64690432e+08
## HELP process_virtual_memory_max_bytes Maximum amount of virtual memory available in bytes.
## TYPE process_virtual_memory_max_bytes gauge
process_virtual_memory_max_bytes 1.8446744073709552e+19
```
<!-- markdownlint-enable line-length -->

</details>
