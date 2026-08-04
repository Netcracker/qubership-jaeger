# Recipe — runtime validation stack — Python delta

Preconditions, topology, platform env, minimal install, runtime order, and teardown:
[`opentelemetry-tracing-common/recipes/validation-stack.md`](../../opentelemetry-tracing-common/recipes/validation-stack.md).

Python specifics below.

## Propagation assert

The wire-header assert matters in Python: `B3SingleFormat` emits the single `b3` header while the plan may say
`b3multi`. Confirm the propagator class, then confirm the headers on the wire.

## No spans in the backend — Python checks first

1. **SDK initialized after the fork.** Under gunicorn/uwsgi with several workers, a provider created in the parent and
   inherited across a fork exports nothing from the workers. Initialize per worker, or use `--preload` deliberately —
   see [`config-migration.md`](config-migration.md) §Short-lived processes.
2. **Instrumentor never called.** `FastAPIInstrumentor.instrument_app()` / `DjangoInstrumentor().instrument()` missing
   from the startup path leaves the framework uninstrumented while the SDK looks configured.
3. **Auto-launcher not in the entrypoint.** `opentelemetry-instrument` must wrap the actual process command; a
   Dockerfile `CMD` that a Helm `command` replaces silently drops it.
4. **Process exits before flush.** A worker or CLI that exits without shutting the provider down drops the queued batch.

Then continue with the shared list.
