# Build and registry notes — TypeScript / Node delta

Shared blocker handling, smoke-vs-validation rule, and the provenance table:
[`opentelemetry-tracing-common/reference/build-preconditions.md`](../../opentelemetry-tracing-common/reference/build-preconditions.md).

Node specifics below. Two of them are build-time **tracing** blockers, not build
hygiene — a correct-looking migration ships zero spans when either is missed.

## The typecheck is the compile check

A wrong import, a missing type, or a broken API surface fails at `tsc`/bundle time,
not only at runtime. The post-L4 build check is a clean install (`npm ci` /
`yarn install --frozen-lockfile` / `pnpm i --frozen-lockfile`) plus the documented
`tsc`/`build`, or a `tsc --noEmit` typecheck —
[`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md). Write
the install and build commands into `buildProvenance.buildCommand`.

A plain-JavaScript service has no `tsc` gate. There the check is the clean install
plus a smoke run that loads the bootstrap the way the entrypoint does
(`node -r ./dist/tracing.js -e ""`, or `node --import ./dist/tracing.mjs -e ""` on
ESM). Do not fail a JavaScript service for a missing compile step.

## Load order

The tracing bootstrap must initialize before instrumented modules load. CommonJS
`node -r ./tracing.js` or `require('./tracing')` first is fine; an ESM top-level
`import './tracing.js'` is **not**, because imports hoist — use
`node --import ./tracing.mjs`.

That fixes load order only. For the `launcher` mechanism (auto-instrumentation) on
ESM, `--import` alone is not enough: monkey-patch instrumentation wraps `require`,
which ESM never calls, so add
`--experimental-loader=@opentelemetry/instrumentation/hook.mjs` **together with**
`--import`, not as a substitute for it. On Node 20.6 and newer, prefer `register()`
from `node:module` inside the bootstrap — Node warns that `--experimental-loader`
may be removed; the form to plan is in
[`../models/4-transformation.md`](../models/4-transformation.md) §ESM loader hook.
`hand-spans` needs only `--import`.

Verify the entrypoint (`package.json` `scripts.start`, Dockerfile `CMD`,
`NODE_OPTIONS`) actually loads it first.

## Bundling

esbuild / webpack / rollup / tsup / `ncc` inline `require`/`import`, so monkey-patch
instrumentation has nothing to wrap. A bundled service either externalizes the
instrumented dependencies (keep them in `node_modules`, mark them `external`) or
switches to `hand-spans`.

If `discovery-result.service.bundled` is true and the plan keeps auto-instrumentation
without externalizing, downgrade the runtime tier until it is resolved: set
`validationPlan.runtime.status` to `manual`, `buildProvenance.matchesL4` to `false`,
and record the blocker in plan `gaps`
(`build blocked: bundler-defeats-instrumentation — <what is bundled>`).

## Private npm registries

Node services often install from a private registry (internal npm mirror, GitHub
Packages, `.npmrc` `@scope:registry`, auth tokens). Record the blocker as
`build blocked: private-registry — <scope>`; the handling is the shared one. A 404
on a private scope is an auth failure, not a missing package.

## Provenance evidence

`buildProvenance` has no Node-specific command field. Record the install and build
commands in `buildCommand` and `detail`, together with `imageTag` and
`purgedImages`.

When a pre-built image is reused, compare its installed package set against the
current manifest and the L4 diff (`npm ls @opentelemetry/sdk-node` inside the image,
or inspect the baked-in lockfile) before accepting `ci-image`.
