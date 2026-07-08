# Service installation discovery

Layer 5 runtime validation depends on **how this specific service is installed and
tested**. That path is unknown until discovery runs in the target repository.
This skill does **not** invent a service-specific Maven/Docker pipeline. It
derives build/deploy commands from the service's own docs, CI, or scripts, then
uses the Java fresh-build recipe to produce a post-L4 artifact when runtime e2e
is in scope.

## Step 1 — Find installation documentation

Search the repository (and linked docs) for install/run guidance. Typical
locations:

| Signal              | Examples                                                                                         |
|---------------------|--------------------------------------------------------------------------------------------------|
| Install docs        | `docs/installation/**`, `docs/installation/parameters.md`, `README.md` (install/deploy sections) |
| Helm / charts       | `helm-templates/**`, `charts/**`, `values.yaml` + companion parameter docs                       |
| Local bootstrap     | `bootstrap/`, `local.mk`, `Makefile`, `skaffold.yaml`, `docker-compose*.yml`                     |
| CI deploy + test    | `.github/workflows/*integration*`, `integration-tests.yml`, `deploy-*.yml`                       |
| Operator / platform | `docs/deployment/**`, product README in monorepo root                                            |

Record every path found in the runtime `scenario`, evidence prose, or L5 brief
with file citations. Use plan root `gaps` only for blockers: missing docs,
missing credentials, unclear install scope, or skipped runtime.
If multiple guides exist, prefer the one that matches the **same scope** the
migration targets (e.g. Helm production vs a local bootstrap flow).

## Step 2 — Derive the runtime path from docs

When installation docs exist, **follow them** for runtime validation — do not invent
a parallel pipeline:

- image source (registry tag, local build command **as documented**);
- prerequisites (DB, secrets, `GITHUB_TOKEN`, cluster tools);
- how integration or smoke tests are run after deploy.

If docs say the image must be built with private registry credentials, record that
in `gaps` and set `runtime.status` to `manual`. Do not attempt undocumented
workarounds (agent overlays, stock images without the migration changes).

## Step 3 — No install doc: integration tests

If no installation guide is found, inspect whether **integration tests** define a
repeatable run path:

- `dbaas-integration-tests`, `*-integration-tests` modules;
- `mvn` profiles (`integration-test`, `-DskipIT=false`);
- scripts under `.github/scripts/`, `bootstrap/`, `validation-image/`;
- documented env vars (`GITHUB_TOKEN`, `CONFIG_FILE`, cluster name).

Decide explicitly:

- **Clear** — cite the command(s) and prerequisites; propose runtime validation
  aligned with that harness (tracing assertions still apply).
- **Unclear** — do not guess. Ask the user (see below).

## Step 4 — Ask the user

When installation docs are missing and the integration-test path is not
self-explanatory, stop and ask:

1. How is this service normally installed for dev or CI (cluster, compose, none)?
2. Is there a prebuilt image or a required build step (and where credentials live)?
3. Should runtime tracing validation run here, or only static + configuration?

Keep `runtime.status` as `manual` until the user answers.

## Out of scope for this skill

- Resolving Maven 401s, wiring `settings.xml`, or chaining local clones to force a
  build — note the blocker in `gaps`, do not spend the session on it unless the
  user explicitly asks to build and supplies credentials/steps.
- Standing up a full platform stack when docs describe a different path.
- Replacing the service's integration-test harness with an invented one.

For a throwaway tracing backend only (Jaeger + `nc-diagnostic-agent` alias), see
[`../recipes/validation-stack.md`](../recipes/validation-stack.md) — use it **after**
the service install path is known, not as a substitute for it.
