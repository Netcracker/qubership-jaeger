# Service installation discovery (shared)

Layer 5 runtime validation depends on **how this specific service is installed and
run**. That path is unknown until discovery inspects the target repository. The
skill never invents a build/deploy pipeline: it derives the commands from the
service's own docs, CI, or scripts, then uses the language fresh-build recipe to
produce a post-L4 artifact when runtime end-to-end is in scope.

Discovery is **read-only** — record the commands, do not run them. Install, build,
image, and deploy execution belongs to Phase 2 and needs the runtime opt-in in the
language `SKILL.md` §3.3.

Language packages add their own manifest, entrypoint, and packaging signals in
`reference/service-installation-discovery.md`; the steps below are the same
everywhere.

## Step 1 — Find installation documentation

| Signal | Examples |
| --- | --- |
| Install docs | `docs/installation/**`, `README.md` install/deploy sections |
| Helm / charts | `charts/**`, `helm/**`, `helm-templates/**`, `values.yaml` + parameter docs |
| Local bootstrap | `Makefile`, `Taskfile.yml`, `bootstrap/`, `skaffold.yaml`, `docker-compose*.yml`, `Dockerfile` |
| CI deploy + test | `.github/workflows/*integration*`, `deploy-*.yml` |
| Operator / platform | `docs/deployment/**`, product readme in a monorepo root |

Record every path found in `validationPlan.runtime.scenario` or the L5 brief with
file citations. If several guides exist, prefer the one matching the **same scope**
the migration targets (Helm production vs a local bootstrap flow). Reserve plan
root `gaps` for blockers: missing docs, missing credentials, unclear install scope,
skipped runtime.

## Step 2 — Derive the runtime path

Follow the documented flow; do not build a parallel pipeline. Capture:

- dependency install / build command, as documented;
- image build command and image layout (which files reach the runtime stage);
- deploy command;
- process entrypoint — how the service actually starts;
- prerequisites and secrets (DB, tokens, volumes) and the env-injection surface
  where `TRACING_*` reaches the container;
- test command or traffic-generation method.

One documented deviation is mandatory: the L5 image tag must be **session-unique**,
never the documented `:latest`/`:dev` tag — a reused tag makes the runtime tier
`manual` at best. Record the commands actually run in
`validationPlan.runtime.buildProvenance.detail`.

If the docs require credentials that are unavailable, record the blocker per
[`build-preconditions.md`](build-preconditions.md) and set `runtime.status` to
`manual`. Do not attempt undocumented workarounds (agent overlays, stock images
without the migration changes).

## Step 3 — No install doc: integration tests

When no installation guide exists, check whether integration tests define a
repeatable run path (test modules, build profiles, scripts under
`.github/scripts/` or `bootstrap/`, documented env vars).

- **Clear** — cite the commands and prerequisites; align runtime validation with
  that harness (tracing assertions still apply).
- **Unclear** — do not guess; ask (Step 4).

## Step 4 — Ask the user

1. How is this service normally installed for dev or CI (cluster, compose, none)?
2. Is there a prebuilt image or a required build step, and where do credentials live?
3. Should runtime tracing validation run here, or only static + configuration?

Keep `validationPlan.runtime.status` at `manual` until the user answers.

## Out of scope

- Resolving registry authentication, wiring credential files, or chaining local
  clones to force a build — record the blocker in `gaps` and move on, unless the
  user explicitly asks to build and supplies credentials or steps.
- Standing up a full platform stack when the docs describe a different path.
- Replacing the service's integration-test harness with an invented one.

For a throwaway tracing backend only, see the language
`recipes/validation-stack.md` — use it **after** the service install path is known,
not as a substitute for it.
