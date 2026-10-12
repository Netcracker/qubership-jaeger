# Service installation discovery — TypeScript / Node delta

Shared steps 1–4, evidence rules, and the out-of-scope list:
[`opentelemetry-tracing-common/reference/service-installation-discovery.md`](../../opentelemetry-tracing-common/reference/service-installation-discovery.md).

Node adds the signals below. They are not cosmetic: the entrypoint, the module system, and the image layout decide
whether the tracing bootstrap loads at all.

## Step 1 — extra search locations

- `package.json` `scripts` (`build`, `start`, `start:prod`, `serve`, `dev`), `packageManager`, `engines`;
- `.dockerignore` — it can exclude `dist/` or the tracing bootstrap from the image;
- workspace markers — root `package.json` `workspaces`, `pnpm-workspace.yaml`, `lerna.json`, `nx.json`, `turbo.json`,
  and whether the Dockerfile builds from the repository root or from a pruned subtree (`turbo prune --docker`);
- Node version — `.nvmrc`, `engines.node`, the Dockerfile base image tag, CI `setup-node`. The major decides the ESM
  hook form: `--import` needs Node 18.19+/20.6+, and `register()` from `node:module` supersedes
  `--experimental-loader` from 20.6 on;
- `tsconfig.json` (`outDir`, `module`, `moduleResolution`), bundler config (`esbuild` / `webpack` / `rollup` / `tsup`),
  `.npmrc`, `Procfile`.

## Step 2 — extra capture

- package manager, chosen from evidence rather than preference: the committed lockfile (`package-lock.json` →
  `npm ci`, `yarn.lock` → `yarn install --frozen-lockfile`, `pnpm-lock.yaml` → `pnpm i --frozen-lockfile`), the
  `packageManager` field, or a Corepack call in CI. With **no** committed lockfile `npm ci` cannot run — use
  `npm install` and record the weaker provenance in `gaps`;
- in a workspace repository: the directory the install runs in (the root, not the package) and the filtered build
  command (`npm run build -w <pkg>`, `pnpm --filter <pkg> build`, `turbo run build --filter=<pkg>`);
- build/compile command (`tsc`, `npm run build`, bundler command) and output directory;
- **image layout** — multi-stage or single-stage, whether the runtime stage prunes dev dependencies
  (`npm ci --omit=dev`, `npm prune --production`, `NODE_ENV=production`), and which files it copies (`dist/`,
  `node_modules/`, the tracing bootstrap). This decides whether L4 may put OTel packages in `devDependencies`
  (it may not — [`../recipes/validation-stack.md`](../recipes/validation-stack.md) §No spans in the backend);
- module system (ESM/CJS) and whether the artifact is bundled;
- the env-injection surface for `TRACING_*` and `NODE_OPTIONS` — Helm `values.yaml` keys plus the template consuming
  them, Deployment `env`/`envFrom`, ConfigMap, `.env` + `dotenv`, or a NestJS `ConfigModule` schema that rejects
  unknown keys.

## Entrypoint precedence (Node-specific)

Resolve how the process starts and whether the tracing bootstrap loads first. Record the winner verbatim:

1. Helm/manifest `command` + `args` — overrides the image;
2. Dockerfile `ENTRYPOINT`/`CMD`, including `NODE_OPTIONS` from `ENV` or from container `env`;
3. `package.json` `scripts.start` / `start:prod`, when the image runs `npm start`.

Forms to expect: `node dist/main.js`, `node -r ./tracing.js`, `node --import ./tracing.mjs`, `nest start`, PM2/cluster.
A Dockerfile `-r` that a Helm `command` silently replaces is a finding, not a detail.

Reuse `discovery-result.service.entrypoint`, `service.moduleSystem`, `service.bundled`, and `instrumentation.hook` from
L1 — do not re-derive them. When the deploy path launches something different from what L1 recorded, **the deploy path
wins**: correct the L1 value and record the disagreement in `gaps`
(`entrypoint mismatch: <L1 value> vs <deploy value>`).

Load-order and bundling consequences: [`build-preconditions.md`](build-preconditions.md).
