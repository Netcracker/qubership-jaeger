# Repository agent instructions

## Scope

- This repository maintains the Qubership Jaeger Helm chart, supporting images, integration tests, and MkDocs documentation.
- This file contains repository-wide guidance; keep component-specific guidance with the affected component.

## Repository map

- `charts/qubership-jaeger/` contains the chart templates, default values, and JSON schema.
- `readiness-probe/` is the standalone Go module and container image for storage readiness checks.
- `integration-tests/robot/` contains Robot Framework suites that run in the chart's test-runner Pod.
- `docs/` and `mkdocs.yml` define the published documentation site.
- `agent-packages/troubleshoot-jaeger/` contains the APM troubleshooting package for Jaeger incidents.

## Commands

- Test the Go module from `readiness-probe/`: `go test ./...`.
- Build documentation after installing `requirements_mkdocs.txt`: `mkdocs build --verbose --strict`.
- Run the documented Super-Linter command from `README.md` for changes covered by repository linting:

  ```bash
  docker run \
    -e RUN_LOCAL=true \
    -e DEFAULT_BRANCH=$(git rev-parse --abbrev-ref HEAD) \
    --env-file .github/super-linter.env \
    -v ${PWD}:/tmp/lint \
    --rm \
    ghcr.io/super-linter/super-linter:slim-$(sed -nE 's#.*uses:\s+super-linter/super-linter/slim@([^\s]+).*#\1#p' .github/workflows/super-linter.yaml)
  ```

## Done when

- Run the applicable checks above; `.github/workflows/go-test.yaml` is the CI gate for `readiness-probe/`.
- For chart or integration-test changes, account for the Kind-based installation test in `.github/workflows/integration-tests.yml`.
- Report checks run and checks not run, including any required live-cluster validation.

## Context routing

- Before changing chart configuration, read `docs/installation.md` and the relevant `docs/examples/` page to keep values and documented examples aligned.
- Before changing Robot suites or their chart wiring, read `integration-tests/README.md` for test tags, prerequisites, and deployment parameters.
- Before opening a pull request, read `CONTRIBUTING.md` for contribution requirements.
