# Recipe — runtime validation stack — TypeScript / Node delta

Preconditions, topology, platform env, minimal install, runtime order, and teardown:
[`opentelemetry-tracing-common/recipes/validation-stack.md`](../../opentelemetry-tracing-common/recipes/validation-stack.md).

Node specifics below.

## Propagation assert

The wire-header assert matters in Node: a bare `new B3Propagator()` emits the single `b3` header while the plan may say
`b3multi`. Confirm the constructor option, then confirm the headers on the wire.

The entry span appearing at all also confirms the Node load-order and bundler fixes worked — an ESM hoist, or a bundler
that ate the monkey-patch, shows up here as **no** entry span despite a clean build.

## No spans in the backend — Node checks first

These four account for most "clean build, empty trace" cases:

1. **Load order.** The tracing bootstrap must initialize before instrumented modules. ESM top-level
   `import './tracing.js'` is hoisted and runs too late — use `--import` (or CJS `-r`). On ESM with the
   `launcher`/auto-instrumentation mechanism, confirm the loader hook is present **alongside** `--import`:
   `register()` from `node:module` on Node 20.6+, or the older
   `--experimental-loader=@opentelemetry/instrumentation/hook.mjs`
   ([`../models/4-transformation.md`](../models/4-transformation.md) §ESM loader hook). Without it, monkey-patch
   instrumentation cannot wrap an ESM `import` even when load order is correct, and the symptom is identical. Verify
   the actual entrypoint (`scripts.start`, Dockerfile `CMD`, `NODE_OPTIONS`).
2. **Bundler.** A bundled artifact (esbuild/webpack/tsup/ncc) leaves monkey-patch auto-instrumentation nothing to wrap
   — externalize the instrumented dependencies, or switch to hand-spans.
3. **Pruned dependencies.** A runtime stage built with `npm ci --omit=dev`, `npm prune --production`, or
   `NODE_ENV=production` drops OTel packages that L4 put in `devDependencies`. The symptom is identical to a
   load-order bug — check the installed set inside the image
   ([`fresh-build-and-image.md`](fresh-build-and-image.md)).
4. **Duplicate `@opentelemetry/api`.** Two copies in `node_modules` split the global tracer/propagator registry, so
   instrumentation and app code write to different globals. `npm ls @opentelemetry/api` must show one resolved version
   ([`dependency-migration.md`](dependency-migration.md)).

Then continue with the shared list — for Node, `exporter-trace-otlp-http` sends JSON, so the contract `http/protobuf`
needs `exporter-trace-otlp-proto`.
