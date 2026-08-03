# Framework coverage (Java)

This list is the **single source of truth** for which Java frameworks are first-class in this package. Detection is
signature-based, so treat the list as extensible coverage rather than a hard gate: anything not confidently classified
falls back to `unknown` plus the conservative SDK path.

First-class framework families, matching the `service.framework` schema enum:

- `spring-boot` — Spring Boot 3 and Spring Boot 4. The two share the enum value but are **different migration targets**:
  Boot 4 additionally requires `spring-boot-micrometer-tracing-opentelemetry` and the Boot 4
  `management.tracing.export.*` keys. Record the detected major in the L1 brief and in the plan, never in the enum.
- `quarkus` — the `quarkus-opentelemetry` extension, wired at build time.
- `pure-java` — library, worker, or service with manual OTel SDK wiring.

Best-effort families — detect generically and emit `framework=unknown`, then name the identified framework and the
chosen instrumentation in the plan `gaps` so a reviewer can see what was assumed:

- Micronaut → `micronaut-tracing-opentelemetry-http`;
- Helidon → the built-in OTel support of the Helidon major in use;
- Vert.x → `opentelemetry-instrumentation-vertx` or the OTel Java agent;
- Jakarta EE / Dropwizard → the OTel Java agent, or manual SDK wiring where the agent is not viable.

Prefer a matching framework OTel module over the bare SDK whenever one is confidently identified. Fall back to
`framework=unknown` with the conservative SDK path only when no module exists or the framework cannot be identified
with confidence.
