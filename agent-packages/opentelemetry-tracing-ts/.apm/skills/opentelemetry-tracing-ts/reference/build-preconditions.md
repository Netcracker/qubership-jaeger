# Build and registry notes (TypeScript / Node)

Use this file to **detect** build blockers and enforce **fresh-build** rules
before runtime end-to-end.

**Runtime end-to-end after Layer 4:** the agent **must** run
[`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md)
(clean install + typecheck/compile + container image in the same session) before
runtime deploy. Plan-only / audit runs without runtime deploy may defer build and
set `validationPlan.runtime.status` to `manual`.

Install path discovery:
[`service-installation-discovery.md`](service-installation-discovery.md).

## There is a compiler — the typecheck is the check

Unlike Python, TypeScript **has** a build step. A wrong import, a missing type, or
a broken API surface fails at `tsc`/bundle time, not only at runtime. The
fresh-build recipe uses that: a clean install (`npm ci` /
`yarn install --frozen-lockfile` / `pnpm i --frozen-lockfile`) plus the documented
`tsc`/`build` (or `tsc --noEmit` typecheck) is the compile check. A migration that
"looks applied" in `.ts` source but was never compiled and installed into the
image is unverified — treat it as such. (For plain-JS files there is no `tsc`
gate; fall back to a smoke run + `require`/`import` of the bootstrap, like the
interpreted-language recipes.)

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
  with** `--import`, not as a substitute for it. `hand-spans` needs only
  `--import`. Verify the entrypoint (`package.json` `scripts.start`, Dockerfile
  `CMD`, `NODE_OPTIONS`) actually loads it first.
- **Bundling.** esbuild/webpack/rollup/tsup/`ncc` inline `require`/`import`, so the
  monkey-patch instrumentation has nothing to wrap. A bundled service either
  externalizes the instrumented dependencies (keep them in `node_modules`, mark
  them `external`) or switches to `hand-spans`. If `discovery.service.bundled` is
  true and the plan keeps auto-instrumentation without externalizing, record
  `runtime.buildBlocked: bundler-defeats-instrumentation` and downgrade the runtime
  tier until resolved.

## Private package registries

Some Node services install from private registries (internal npm mirror, GitHub
Packages, `.npmrc` `@scope:registry`, auth tokens). If post-L4 install fails due
to auth (401/403 or 404 on a private scope):

1. record blocker in `gaps` (`runtime.buildBlocked: private-npm-registry`);
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
purge stale artifacts and cached SUT images → clean install + typecheck/compile
after Layer 4 → build a session-unique image → deploy only that image, never a tag
left from a previous agent run.

Record how the SUT artifact was produced in the L5 summary and in
`validationPlan.runtime.buildProvenance`:

| Provenance | Valid for L4 tracing validation? |
| ------------------------------------------------------------------------------------------- | ------------------------------------- |
| Fresh **clean install + compile** + new image **in this session** | **Yes** (default for `pass`) |
| CI image tagged to the **current** commit/branch and proven to include current L4 changes | Yes, if provenance matches the diff |
| Pre-existing local image (`:e2e`, `:local`, `:latest`) without reinstall/rebuild | **No** — max `fail` |
| Public/stock image without L4 changes | **No** |

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
