# Service installation discovery (TypeScript / Node)

Layer 5 runtime validation depends on how the specific Node service is installed,
built, and run.

Discovery is **read-only**: record these commands, do not run them. Install, build,
image, and deploy execution belongs to Phase 2 and needs the runtime opt-in in
[`../SKILL.md`](../SKILL.md) §3.3. When the documented path is blocked, record the
blocker in `gaps` — never improvise a substitute install.

## Step 1 — Find install/build docs

Search:

- `README.md` install/deploy sections;
- `docs/installation/**`;
- `charts/**`, `helm/**`, `values.yaml`;
- `Dockerfile`, `docker-compose*.yml`, `Makefile`, `Taskfile.yml`;
- `package.json` `scripts` (`build`, `start`, `start:prod`, `serve`, `dev`),
  `packageManager`, `engines`, and `.dockerignore` — it can exclude `dist/` or the
  tracing bootstrap from the image;
- workspace markers — root `package.json` `workspaces`, `pnpm-workspace.yaml`,
  `lerna.json`, `nx.json`, `turbo.json`, and whether the Dockerfile builds from the
  repository root or from a pruned subtree (`turbo prune --docker`);
- Node version — `.nvmrc`, `engines.node`, the Dockerfile base image tag, CI
  `setup-node`. The major decides the ESM hook form: `--import` needs Node
  18.19+/20.6+, and `register()` from `node:module` supersedes
  `--experimental-loader` from 20.6 on;
- `tsconfig.json` (`outDir`, `module`, `moduleResolution`), bundler config
  (`esbuild`/`webpack`/`rollup`/`tsup`), `.npmrc`, `Procfile`;
- CI workflows with build/integration or deploy jobs.

## Step 2 — Derive runtime path

Use the service-documented build/run flow; do not invent a parallel pipeline. One
documented deviation is mandatory: the L5 image tag must be **session-unique**,
never the documented `:latest`/`:dev` tag — a reused tag makes the runtime tier
`manual` at best. See
[`../recipes/fresh-build-and-image.md`](../recipes/fresh-build-and-image.md).

Capture:

- package manager, chosen from evidence rather than preference: the committed
  lockfile (`package-lock.json` → `npm ci`, `yarn.lock` →
  `yarn install --frozen-lockfile`, `pnpm-lock.yaml` → `pnpm i --frozen-lockfile`),
  the `packageManager` field, or a Corepack call in CI. With **no** committed
  lockfile `npm ci` cannot run — use `npm install` and record the weaker provenance
  in `gaps`;
- in a workspace repository: the directory the install runs in (the root, not the
  package) and the filtered build command (`npm run build -w <pkg>`,
  `pnpm --filter <pkg> build`, `turbo run build --filter=<pkg>`);
- build/compile command (`tsc`, `npm run build`, bundler command) and output dir;
- image build command **and image layout** — multi-stage or single-stage, whether
  the runtime stage prunes dev dependencies (`npm ci --omit=dev`,
  `npm prune --production`, `NODE_ENV=production`), and which files it copies
  (`dist/`, `node_modules/`, the tracing bootstrap). L4 OTel packages must land in
  `dependencies`: from `devDependencies` they are pruned out of the image, and the
  result looks exactly like a load-order failure — clean build, empty trace;
- deploy command;
- app entrypoint — **how the process starts and whether the tracing bootstrap loads
  first**. Resolve it in precedence order and record the winner verbatim:
  1. Helm/manifest `command` + `args` — overrides the image;
  2. Dockerfile `ENTRYPOINT`/`CMD`, including `NODE_OPTIONS` from `ENV` or from
     container `env`;
  3. `package.json` `scripts.start` / `start:prod`, when the image runs `npm start`.

  Forms to expect: `node dist/main.js`, `node -r ./tracing.js`,
  `node --import ./tracing.mjs`, `nest start`, PM2/cluster. A Dockerfile `-r` that a
  Helm `command` silently replaces is a finding, not a detail;
- module system (ESM/CJS) and whether the artifact is bundled;
- required dependencies/secrets **and the env-injection surface** — where
  `TRACING_*` and `NODE_OPTIONS` reach the container (Helm `values.yaml` keys plus
  the template consuming them, Deployment `env`/`envFrom`, ConfigMap, `.env` +
  `dotenv`, a NestJS `ConfigModule` schema that rejects unknown keys). The L5 stand
  sets the contract variables through this surface;
- test command or traffic generation method.

Reuse `discovery-result.service.entrypoint`, `service.moduleSystem`,
`service.bundled`, and `instrumentation.hook` from L1 — do not re-derive them. When
the deploy path launches something different from what L1 recorded, **the deploy
path wins**: correct the L1 value and record the disagreement in `gaps`
(`entrypoint mismatch: <L1 value> vs <deploy value>`).

Record the install path in `validationPlan.runtime.scenario` with file citations,
and the commands actually run in `validationPlan.runtime.buildProvenance.detail`.
Reserve `gaps` for blockers: missing docs, missing credentials, unclear install
scope, skipped runtime.

The entrypoint and module system matter for tracing: they decide where and how the
SDK must be loaded (see [`build-preconditions.md`](build-preconditions.md) load-order
and bundling notes, and [`../recipes/config-migration.md`](../recipes/config-migration.md)).

## Step 3 — If unclear, ask user

When the install path is not discoverable:

1. ask where the service is usually deployed (cluster/local);
2. ask where build credentials / private registry access are provided;
3. ask whether runtime validation is in scope now.

Keep `validationPlan.runtime.status` at `manual` until clarified.
