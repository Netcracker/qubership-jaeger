# Recipe — trace IDs in logs

Adding `traceId`/`spanId` to the log pattern is **mandatory** on the platform
([`platform-tracing-guide.md`](../../opentelemetry-tracing-common/reference/platform-tracing-guide.md)
§ Log correlation), so a migration plan must include it whenever the service
writes logs. The goal: every log line emitted inside a span carries the trace
and span IDs, so logs and traces correlate.

Expected log shape:

```text
[yyyy-MM-ddTHH:mm:ss.SSS] ... [traceId=<value>] [spanId=<value>] ...
```

First check whether the project's logging setup already injects the fields — if
they are present in current logs, skip this recipe.

## Spring Boot — Log4j2 / Slf4j

Dependency (version from the instrumentation BOM):

```xml
<dependency>
  <groupId>io.opentelemetry.instrumentation</groupId>
  <artifactId>opentelemetry-log4j-context-data-2.17-autoconfigure</artifactId>
  <scope>runtime</scope>
</dependency>
```

Pattern uses MDC keys `trace_id` / `span_id`:

```xml
<PatternLayout pattern="[%d{ISO8601}][%level]...[traceId=%X{trace_id}][spanId=%X{span_id}]... %msg%n"/>
```

## Spring Boot — Logback

```xml
<dependency>
  <groupId>io.opentelemetry.instrumentation</groupId>
  <artifactId>opentelemetry-logback-mdc-1.0</artifactId>
  <scope>runtime</scope>
</dependency>
```

```xml
<pattern>[%d{"yyyy-MM-dd'T'HH:mm:ss,SSS"}][%level]...[traceId=%X{trace_id}][spanId=%X{span_id}]... %msg%n</pattern>
```

## Quarkus

Quarkus exposes the fields as `traceId` / `spanId` (note the camelCase):

```properties
quarkus.log.console.format=... [traceId=%X{traceId}][spanId=%X{spanId}] ...
```

Access log:

```properties
quarkus.http.access-log.pattern=... [traceId=%{X,traceId}][spanId=%{X,spanId}] ...
```

## Verify

After the change, generate traffic and confirm a real log line shows non-empty
`traceId`/`spanId`, and that the same `traceId` appears for the span in Jaeger.
