# Recipe — post-validation cleanup (L5)

Run **only** when `validationPlan.runtime.status` is `pass`. See
[`../models/5-validation.md`](../models/5-validation.md) §5.4.

Remove the artifacts created for runtime validation so they are not accidentally
committed. Everything the migration itself produced stays — see **Retain** below.

## Ephemeral (typical)

- `e2e-*.yaml`, `*-minimal.yaml`, throwaway k8s/compose overlays
- one-off shell scripts (`e2e-run-*.sh`) written only for L5
- `Dockerfile.e2e`, `Dockerfile.e2e.local`
- copied build credentials in the service tree (e.g. Maven `settings.xml`) used only for validation
- temporary namespace/bootstrap manifests not part of the product install path

## Retain

- migrated dependency manifest (`go.mod`, `pom.xml`, etc.)
- application config, Helm templates, tracing modules (e.g. `internal/tracing/*`)
- the tracing backend and SUT manifests that are the documented install path
- documentation updated during L4 apply
- files the user explicitly asked to keep for repeat validation

## Steps

1. List ephemeral paths created during this session (chat or plan `gaps`).
2. `git status` — confirm ephemeral files are not mixed with L4 product edits.
3. Delete or revert ephemeral files (`git checkout -- <path>` or `rm`).
4. Post **L5 Cleanup** in chat: removed paths, or `none — no ephemeral artifacts`.
5. If the user asked to retain artifacts, record `cleanup skipped — <reason>` in `gaps`.

Never commit ephemeral validation files unless the user explicitly asks for them.
