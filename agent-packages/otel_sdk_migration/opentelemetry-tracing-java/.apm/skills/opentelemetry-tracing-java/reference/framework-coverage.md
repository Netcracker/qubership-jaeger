# Framework coverage (Java)

This list is the source of truth for which Java frameworks are first-class in this package; the `service.framework`
enum in [`../schemas/L1-discovery-result.schema.json`](../schemas/L1-discovery-result.schema.json) is this list plus
`unknown`, and the two are extended together. Coverage is extensible, not a hard gate: detection is signature-based,
and a framework that is not classified confidently falls back to `framework=unknown` plus the conservative SDK path.

When a best-effort framework **is** identified confidently, prefer its matching OTel module over the bare SDK and
record the framework and the choice in the plan `gaps`, so a reviewer sees what was assumed.

First-class framework families:

- `spring-boot` — Spring Boot 3 and Spring Boot 4. The two share the enum value but are **different migration targets**:
  Boot 4 additionally requires `spring-boot-micrometer-tracing-opentelemetry` and the Boot 4
  `management.tracing.export.*` keys. Record the detected major in the L1 brief and in the plan, never in the enum.
- `quarkus` — the `quarkus-opentelemetry` extension, wired at build time.
- `pure-java` — library, worker, or service with manual OTel SDK wiring.

Best-effort families — detect generically, keep `framework=unknown`, and plan the module named here:

- Micronaut → `micronaut-tracing-opentelemetry-http`;
- Helidon → the built-in OTel support of the Helidon major in use;
- Vert.x → `opentelemetry-instrumentation-vertx` or the OTel Java agent;
- Jakarta EE / Dropwizard → the OTel Java agent, or manual SDK wiring where the agent is not viable.
