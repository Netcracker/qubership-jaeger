# Service installation discovery (TypeScript / Node)

Layer 5 runtime validation depends on how the specific Node service is installed,
built, and run.

## Step 1 — Find install/build docs

Search:

- `README.md` install/deploy sections;
- `docs/installation/**`;
- `charts/**`, `helm/**`, `values.yaml`;
- `Dockerfile`, `docker-compose*.yml`, `Makefile`, `Taskfile.yml`;
- `package.json` `scripts` (`build`, `start`, `dev`), `bin`, `main`/`module`/`exports`;
- `tsconfig.json` (`outDir`, `module`, `moduleResolution`), bundler config
  (`esbuild`/`webpack`/`rollup`/`tsup`), `.npmrc`, `Procfile`;
- CI workflows with build/integration or deploy jobs.

## Step 2 — Derive runtime path

Use the service-documented build/run flow; do not invent a parallel pipeline.
Capture:

- package manager + install command (`npm ci` / `yarn install --frozen-lockfile` /
  `pnpm i --frozen-lockfile`);
- build/compile command (`tsc`, `npm run build`, bundler command) and output dir;
- image build command;
- deploy command;
- app entrypoint — **how the process starts and whether the tracing bootstrap
  loads first** (`node dist/main.js`, `node -r ./tracing.js`,
  `node --import ./tracing.mjs`, `NODE_OPTIONS`, `nest start`, PM2/cluster);
- module system (ESM/CJS) and whether the artifact is bundled;
- required dependencies/secrets;
- test command or traffic generation method.

The entrypoint and module system matter for tracing: they decide where and how the
SDK must be loaded (see [`build-preconditions.md`](build-preconditions.md) load-order
and bundling notes, and [`../recipes/config-migration.md`](../recipes/config-migration.md)).

## Step 3 — If unclear, ask user

When the install path is not discoverable:

1. ask where the service is usually deployed (cluster/local);
2. ask where build credentials / private registry access are provided;
3. ask whether runtime validation is in scope now.

Keep `runtime.status=manual` until clarified.
