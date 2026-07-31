# Build and registry notes (TypeScript / Node)

Use this file to **detect** build blockers and enforce **fresh-build** rules
before runtime end-to-end.

**Runtime end-to-end after Layer 4:** the agent **must** run
[`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md)
(clean install + build check + container image in the same session) before
runtime deploy. Plan-only / audit runs without runtime deploy may defer build and
set `validationPlan.runtime.status` to `manual`.

Install path discovery:
[`service-installation-discovery.md`](service-installation-discovery.md).

## The typecheck is the compile check

A wrong import, a missing type, or a broken API surface fails at `tsc`/bundle time,
not only at runtime. The fresh-build recipe uses that: a clean install (`npm ci` /
`yarn install --frozen-lockfile` / `pnpm i --frozen-lockfile`) plus the documented
`tsc`/`build` (or a `tsc --noEmit` typecheck) is the compile check. A migration that
"looks applied" in `.ts` source but was never compiled and installed into the image
is unverified — treat it as such.

A plain-JavaScript service has no `tsc` gate. There the check is the clean install
plus a smoke run that loads the bootstrap the way the entrypoint does
(`node -r ./dist/tracing.js -e ""`, or `node --import ./dist/tracing.mjs -e ""` on
ESM). Do not fail a JavaScript service for a missing compile step.

## Load order and bundling are build-time tracing blockers

Two Node-specific failure modes turn a correct-looking migration into no spans at
runtime — check them here, not only at runtime:

- **Load order.** The tracing bootstrap must initialize before instrumented
  modules load. CommonJS `node -r ./tracing.js` or `require('./tracing')` first is
  fine; an ESM top-level `import './tracing.js'` is **not** (imports hoist) — use
  `node --import ./tracing.mjs`. That fixes load order only. For the `launcher`
  mechanism (auto-instrumentation) on ESM, `--import` alone is not enough:
  monkey-patch instrumentation wraps `require`, which ESM never calls, so add
  `--experimental-loader=@opentelemetry/instrumentation/hook.mjs` **together
  with** `--import`, not as a substitute for it. On Node 20.6 and newer, prefer
  `register()` from `node:module` inside the bootstrap — Node warns that
  `--experimental-loader` may be removed; the form to plan is in
  [`../models/4-transformation.md`](../models/4-transformation.md)
  §ESM loader hook. `hand-spans` needs only `--import`. Verify the entrypoint
  (`package.json` `scripts.start`, Dockerfile `CMD`, `NODE_OPTIONS`) actually loads
  it first.
- **Bundling.** esbuild/webpack/rollup/tsup/`ncc` inline `require`/`import`, so the
  monkey-patch instrumentation has nothing to wrap. A bundled service either
  externalizes the instrumented dependencies (keep them in `node_modules`, mark
  them `external`) or switches to `hand-spans`. If `discovery-result.service.bundled`
  is true and the plan keeps auto-instrumentation without externalizing, downgrade
  the runtime tier until it is resolved: `validationPlan.runtime.status` to `manual`,
  `buildProvenance.matchesL4` to `false`, and the blocker in plan `gaps`
  (`build blocked: bundler-defeats-instrumentation — <what is bundled>`). The schema
  has no dedicated blocker field; `gaps` is where blockers live.

## Private package registries

Some Node services install from private registries (internal npm mirror, GitHub
Packages, `.npmrc` `@scope:registry`, auth tokens). If post-L4 install fails due
to auth (401/403 or 404 on a private scope):

1. record the blocker in plan `gaps` (`build blocked: private-npm-registry — <scope>`);
2. set `validationPlan.runtime.status` to `manual` unless the user provides
   credentials or a prebuilt image path from install docs;
3. do **not** validate runtime on a stale pre-L4 image or improvise a substitute
   install.

Distinguish **auth failure** (401/403, registry access denied) from **slow
resolve** (download/peer-dependency resolution in progress, no error yet).

## Smoke vs validation

A stock image or pre-existing tag proves **availability**, not that the tracing
migration works. Never mark the runtime tier `pass` unless the running artifact
includes Layer 4 changes (dependencies, config, bootstrap/mechanism).

Jaeger spans from probe traffic on a **crash-looping or not-Ready** workload are
**smoke only**, not validation — run common
[`recipes/stand-health-gate.md`](../../opentelemetry-tracing-common/recipes/stand-health-gate.md)
before tracing pass/fail.

## Build artifact provenance (mandatory for runtime pass)

Before runtime end-to-end, run [`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md)
— it defines the mandatory sequence for **every** TypeScript validation session:
purge stale artifacts and cached SUT images → clean install + build check after
Layer 4 → build a session-unique image → deploy only that image, never a tag left
from a previous agent run.

Record how the SUT artifact was produced in the L5 summary and in
`validationPlan.runtime.buildProvenance`. The `source` column is the schema enum
value to write:

| Provenance | `source` | Valid for L4 tracing validation? |
| ------------------------------------------------------------------------------------------- | --------------------- | ------------------------------------------------- |
| Fresh **clean install + compile** + new image **in this session** | `fresh-build` | **Yes** (default for `pass`) |
| CI image tagged to the **current** commit/branch and proven to include current L4 changes | `ci-image` | Yes, if provenance matches the diff |
| Pre-existing local image (`:e2e`, `:local`, `:latest`) without reinstall/rebuild | `reused-local-image` | **No** — `manual`, or `fail` if runtime was exercised |
| Public/stock image without L4 changes | `stock-image` | **No** |

`buildProvenance` has no Node-specific command field (its `mavenCommand` /
`runnerJar` are Java-only). Record the install and build commands you actually ran
in `buildProvenance.detail`, together with `imageTag` and `purgedImages`.

Checklist when a pre-built image is reused:

1. Confirm the image was built **after** the current L4 changes (CI run, labels,
   digest, commit SHA).
2. Compare the image's installed package set with the current manifest / L4 diff
   (`npm ls @opentelemetry/sdk-node` inside the image, or inspect the baked-in
   lockfile).
3. If provenance does not match the migrated tree, set `validationPlan.runtime.status`
   to `fail` or `manual` with gap `runtime.reusedImageNotFromCurrentL4Build` — do
   **not** claim the migration is validated.

Example honest summary:

> Runtime end-to-end used pre-existing image `<service>:<tag>` built before L4.
> Tracing export works on that image, but **L4 diff is not build-verified**.
