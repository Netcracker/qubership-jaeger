# Performance
Jaeger collector performance can be affected by many factors.

When you are using Jaeger under high load, you must consider the following:

* **Cassandra resources** - Jaeger can put Cassandra under high load, especially in the `prod` mode.
* **Jaeger Collector resources** - Increasing Jaeger collector resources can also increase Jaeger ability
  to receive spans. However, it should be noted that Cassandra can work better with parallel writes, for example,
  increasing the number of Jaeger replicas. Increasing the collector resources may not always result in more successfully
  processed spans.
* **Jaeger Number of collector Replicas** - Increasing the collector replicas proportionally increases Jaeger's
  ability to receive spans, as long as Cassandra can receive them.
* **Network connection and client configuration** - Client configuration can increase the amount of spans Jaeger
  is able to receive and process. For more information, refer to
  [https://www.jaegertracing.io/docs/1.20/performance-tuning/#modify-the-batched-spans-flush-interval](https://www.jaegertracing.io/docs/1.20/performance-tuning/#modify-the-batched-spans-flush-interval).
* **Collector inner configuration** - Some parameters can be configured within the Jaeger collector itself
  (currently not possible with Jaeger Helm charts). For example, it is possible to configure collector
  queue size or use Kafka in the deployment schema. By the default values that are used in this deployment,
  the queue size is 2000.

## Jaeger Performance Metrics

Jaeger exposes Prometheus metrics. To install the service monitor, you can use the `jaeger.prometheusMonitoring` parameter.

The following is a list of useful Prometheus metrics to check the Jaeger performance:

* **sum(rate(jaeger_collector_spans_received_total[1m]))** - Displays the average number of received spans per second
  in the last minute.
* **sum(rate(jaeger_collector_spans_dropped_total[1m]))** - Displays the average number of dropped spans per second
  in the last minute.
* **jaeger_collector_queue_length** - Displays the queue collector queue length. The collector starts dropping spans
  if this metric reaches 2000.

For more information about Jaeger performance tuning, refer to
[https://www.jaegertracing.io/docs/latest/performance-tuning/](https://www.jaegertracing.io/docs/latest/performance-tuning/).
