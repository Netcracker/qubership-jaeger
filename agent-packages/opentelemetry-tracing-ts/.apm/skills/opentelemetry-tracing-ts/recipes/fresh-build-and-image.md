# Recipe — fresh TypeScript build and container image (TypeScript L5)

When Layer 4 edits exist, run exactly once after L4 and before first runtime deploy.

TypeScript has a compile step, so the "fresh build" is a real typecheck/compile
plus a clean dependency install (so the new OTel packages are actually in the
image), not just a smoke run.

On a **plain-JavaScript** service there is no `tsc` gate — do not fail it for a
missing compile step
([`../reference/build-preconditions.md`](../reference/build-preconditions.md)).
There the gate is the clean install, the documented build/bundle script if one
exists, and a smoke run that loads the bootstrap the way the entrypoint does:
`node -r ./dist/tracing.js -e ""` (CommonJS) or
`node --import ./dist/tracing.mjs -e ""` (ESM).

Install path, package manager, workspace layout, image layout and entrypoint come
from
[`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md).

**Phase gate.** Steps 0.1, 1 and 2 (purge of local build output, install, compile,
image build) are local work. Step 0.2, Step 0.3 and Step 3 touch a runtime
environment: do not run them until the user has opted in to runtime validation and
named the environment ([`../SKILL.md`](../SKILL.md) §3.3). Without that opt-in,
stop after Step 2, set `validationPlan.runtime.status` to `manual`, and record the
built tag in `buildProvenance.imageTag`.

## Step 0 — Purge stale artifacts

1. clean build output (`dist/`, `build/`, `.tsbuildinfo`, bundler caches like
   `.esbuild`/`.webpack`) **and `node_modules/`** — `npm ci` removes it itself, but
   `yarn`/`pnpm` frozen installs only reconcile an existing tree and can keep a
   duplicate `@opentelemetry/api` alive. Confirm `.dockerignore` excludes
   `node_modules/` so the local tree never shadows the image install;
2. remove stale SUT image tags from the active runtime image store — only tags of
   this SUT that this or a previous agent session created, never a tag a foreign
   workload may reference;
3. ensure the deploy manifest references a session-unique image tag.

## Step 1 — Post-L4 clean install + compile (once)

Run only after L4 edits. In a workspace repository install at the **root** and
build filtered (`npm run build -w <pkg>`, `pnpm --filter <pkg> build`,
`turbo run build --filter=<pkg>`); take the directory and filter from
[`../reference/service-installation-discovery.md`](../reference/service-installation-discovery.md).

Commands:

- refresh the lockfile first when L4 changed `package.json`: run the package
  manager's normal install once (`npm install` / `yarn install` / `pnpm install`)
  and commit the updated lockfile. Skip this and the frozen install below fails on
  the drift L4 just created (`npm ci` → `EUSAGE … not in sync`, pnpm →
  `ERR_PNPM_OUTDATED_LOCKFILE`);
- clean install: `npm ci` / `yarn install --frozen-lockfile` /
  `pnpm i --frozen-lockfile`, chosen from the committed lockfile rather than
  preference. With **no** committed lockfile `npm ci` cannot run: use `npm install`
  and record the weaker provenance in `gaps`;
- typecheck/compile: run the build the repository actually has (`npm run build` /
  `tsc` / the documented bundler command) — it must **emit**, because Step 0 purged
  `dist/`. Use `tsc --noEmit` only when the image builds its own compile stage
  (multi-stage Dockerfile) and nothing copies a prebuilt `dist/` from the work tree;
- run the documented test command when a suite exists.

Pass criteria:

- clean install exits 0 with the L4 dependency set resolved (no unmet
  `@opentelemetry/api` peer, no duplicate `api`);
- typecheck/compile exits 0 on TypeScript — a wrong OTel import or API drift fails
  here; on plain JavaScript the bootstrap smoke run exits 0 instead;
- the L4 OTel packages sit in `dependencies`, not `devDependencies` — a runtime
  stage doing `npm ci --omit=dev`, `npm prune --production`, or building with
  `NODE_ENV=production` drops them from the image, and the symptom is identical to
  a load-order bug: clean build, empty trace;
- the tracing bootstrap loads first in the entrypoint (verify
  `scripts.start` / Dockerfile `CMD` / `NODE_OPTIONS` — CJS `-r`, ESM `--import`);
- documented tests pass (or are recorded as absent in `gaps`).

> **Common failure — bundled build, no spans.** If the service bundles
> (esbuild/webpack/tsup/ncc) and keeps auto-instrumentation, the monkey-patch has
> nothing to wrap at runtime — the build succeeds but no server span appears. Fix
> by externalizing the instrumented dependencies from the bundle or switching to
> `hand-spans` ([`../reference/build-preconditions.md`](../reference/build-preconditions.md)),
> not by adding more instrumentation packages.
>
> **Common failure — ESM load order.** A top-level `import './tracing.js'` in an
> ESM entry is hoisted and runs after the instrumented imports are evaluated, so
> instrumentation attaches to nothing. Use `node --import ./tracing.mjs` to fix
> load order. If the mechanism is `launcher`/auto-instrumentation, `--import`
> alone still leaves no spans on ESM — the loader hook has to come with it
> (auto-instrumentation cannot monkey-patch an ESM `import` without it).
> On Node 20.6+ prefer `register()` from `node:module` inside the bootstrap over
> `--experimental-loader`, which Node warns may be removed — the form to plan is in
> [`../models/4-transformation.md`](../models/4-transformation.md) §ESM loader hook.
> `--import` itself needs Node 18.19+/20.6+; on an older major use CJS `-r` and
> record the constraint. `hand-spans` only needs `--import`. The compile passes
> either way; the trace is empty until both are correct.

## Step 2 — Build image

Build the SUT image from the post-L4 tree with an explicitly session-unique tag —
`<service>:l5-<UTC yyyymmdd-HHMMSS>` or `<service>:l5-<short-sha>-<HHMMSS>`, never
`:latest`/`:dev`. When the image is loaded into a local runtime store instead of
pushed to a registry, set `imagePullPolicy: IfNotPresent` (or `Never`) in the
deploy manifest: with `Always` the cluster tries to pull the session tag and fails
with `ImagePullBackOff`.

Then verify the image, do not trust the tag:

- installed packages include the L4 additions — resolver-based, so it also works on
  distroless, pruned and pnpm images:
  `node -p "require('@opentelemetry/sdk-node/package.json').version"` inside the
  image. Use `npm ls @opentelemetry/sdk-node` only when npm is present in the
  runtime stage;
- the bootstrap itself is in the image and post-L4: the file the entrypoint loads
  exists and loads (`node -e "require('./dist/tracing.js')"` for CJS,
  `node --import ./dist/tracing.mjs -e ""` for ESM). For a bundled artifact, that
  the bundle contains the OTel bootstrap and not a stale pre-L4 build;
- the entrypoint loads the bootstrap first.

If any check fails, stop: set `buildProvenance.matchesL4` to `false`,
`validationPlan.runtime.status` to `fail` (when runtime was already exercised) or
`manual`, add gap `runtime.reusedImageNotFromCurrentL4Build`, and do not deploy.

## Step 3 — Runtime availability (after the §3.3 opt-in only)

Load/push the image into the environment the user named, using the documented flow.

## Step 4 — Provenance record

Record in `validationPlan.runtime.buildProvenance`. The schema has
`additionalProperties: false` and **no** Node command field (`mavenCommand` and
`runnerJar` are Java-only), so never invent one:

- `source`: `fresh-build` for this recipe — `ci-image` only for a CI image proven to
  carry the current L4 diff, see
  [`../reference/build-preconditions.md`](../reference/build-preconditions.md);
- `matchesL4`: `true` only when the image checks in Step 2 passed;
- `imageTag`: the session-unique tag actually deployed;
- `purgedImages`: the stale tags removed in Step 0;
- `detail`: the install and build commands actually run, the package manager and
  workspace filter, module system and bundling, and how the bootstrap loads first.

Do not start runtime checks until this recipe is completed or a blocker is
recorded in `gaps`.
