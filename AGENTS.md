# Repository agent instructions

## Scope

- This repository maintains the Qubership Helm chart for deploying Jaeger on Kubernetes and OpenShift.
- Keep this file limited to repository-wide guidance; place component-specific rules near the affected component.

## Repository map

- `charts/qubership-jaeger/` contains the chart, values, schema, templates, and Grafana dashboard.
- `readiness-probe/` is a separate Go module for the storage readiness probe.
- `integration-tests/` contains the Robot Framework image and cluster test suites.
- `docs/` and `mkdocs.yml` define the published documentation site.
- `agent-packages/troubleshoot-jaeger/` contains the APM troubleshooting package.

## Commands

- Run the repository linter from the repository root:

  ```bash
  docker run \
    -e RUN_LOCAL=true \
    -e DEFAULT_BRANCH=$(git rev-parse --abbrev-ref HEAD) \
    --env-file .github/super-linter.env \
    -v ${PWD}:/tmp/lint \
    --rm \
    ghcr.io/super-linter/super-linter:slim-v8.7.0
  ```

- Lint the Helm chart from the repository root: `helm lint charts/qubership-jaeger`.
- Test the readiness probe from `readiness-probe/`: `go test ./...`.
- Build documentation strictly from the repository root after installing `requirements_mkdocs.txt`:
  `mkdocs build --verbose --strict`.
- Run cluster integration through `.github/workflows/integration-tests.yml`; it provisions Kind and required services.

## Non-obvious invariant

- Keep readiness-probe dependency and test work inside `readiness-probe/`; its `go.mod` defines an independent module.

## Done when

- Run the smallest applicable check above, then the repository linter for changes covered by Super-Linter.
- Behavior changes include focused test coverage.
- Documentation changes pass the strict MkDocs build.
- Report checks run, checks not run, and any required live-cluster verification that remains.

## Context routing

- Before changing chart values or templates, read `docs/installation.md` and the relevant file under `docs/examples/`
  to preserve documented configuration behavior.
- Before changing integration tests, read `integration-tests/README.md` and
  `.github/workflows/integration-tests.yml` for test tags, prerequisites, and the cluster execution path.
- Before changing the troubleshooting package, read
  `agent-packages/troubleshoot-jaeger/.apm/skills/troubleshoot-jaeger/SKILL.md` for its package-specific contract.
