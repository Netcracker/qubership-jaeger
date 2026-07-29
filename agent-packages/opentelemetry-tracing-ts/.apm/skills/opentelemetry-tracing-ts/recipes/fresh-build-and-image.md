# Recipe — fresh TypeScript build and container image (TypeScript L5)

When Layer 4 edits exist, run exactly once after L4 and before first runtime deploy.

TypeScript **has** a compile step, so the "fresh build" is a real
typecheck/compile plus a clean dependency install (so the new OTel packages are
actually in the image), not just a smoke run.

## Step 0 — Purge stale artifacts

1. clean build output (`dist/`, `build/`, `.tsbuildinfo`, bundler caches like
   `.esbuild`/`.webpack`);
2. remove stale SUT image tags from the active runtime image store;
3. ensure the deploy manifest references a session-unique image tag.

## Step 1 — Post-L4 clean install + compile (once)

Run only after L4 edits. Typical commands from service docs:

- clean install: `npm ci` / `yarn install --frozen-lockfile` /
  `pnpm i --frozen-lockfile` (uses the lockfile, fails on drift — the point);
- typecheck/compile: `npm run build` / `tsc` / the documented bundler command
  (`tsc --noEmit` is enough as a pure compile check);
- run the documented test command when a suite exists.

Pass criteria:

- clean install exits 0 with the L4 dependency set resolved (no unmet
  `@opentelemetry/api` peer, no duplicate `api`);
- typecheck/compile exits 0 — a wrong OTel import or API drift fails here;
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
> alone still leaves no spans on ESM — add
> `--experimental-loader=@opentelemetry/instrumentation/hook.mjs` **together
> with** `--import` (auto-instrumentation cannot monkey-patch an ESM `import`
> without the loader hook). `hand-spans` only needs `--import`. The compile
> passes either way; the trace is empty until both are correct.

## Step 2 — Build image

Build the SUT image from the post-L4 tree with a session-unique tag. Confirm the
image's installed packages include the L4 additions
(`npm ls @opentelemetry/sdk-node` inside the image, or inspect the baked-in
lockfile), and that the entrypoint loads the bootstrap first.

## Step 3 — Runtime availability

Load/push image into the selected runtime environment using the documented flow.

## Step 4 — Provenance record

Record in `validationPlan.runtime.buildProvenance`:

- install/build command;
- image tag;
- whether the image's dependency set matches the current L4 diff;
- module system + bundling and how the bootstrap is loaded first;
- purged stale tags.

Do not start runtime checks until this recipe is completed or a blocker is
recorded in `gaps`.
