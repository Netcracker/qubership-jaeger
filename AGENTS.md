# Repository agent instructions

## Scope

- This repository maintains the Qubership Helm chart for deploying Jaeger on Kubernetes and OpenShift, together with
  its readiness probe, integration-test image, documentation, and troubleshooting skill.
- This file contains repository-wide guidance; place component-specific instructions next to the affected component.

## Repository map

- `charts/qubership-jaeger/` is the deployable chart, including defaults, schema, and Kubernetes templates.
- `readiness-probe/` is the standalone Go module used by the chart's readiness-probe image.
- `integration-tests/robot/` contains Robot Framework suites executed by the in-cluster test runner.
- `agent-packages/troubleshoot-jaeger/` owns the read-only diagnostic skill and its troubleshooting catalog.
- `docs/` and `mkdocs.yml` are the source and configuration for the published documentation.

## Commands

- Readiness-probe tests: run `go test ./...` from `readiness-probe/`.
- Documentation setup and strict build: run
  `python -m pip install -r requirements_mkdocs.txt && mkdocs build --verbose --strict` from the repository root.

## Non-obvious invariants

- `docs/troubleshooting.md` is a symlink to
  `agent-packages/troubleshoot-jaeger/.apm/skills/troubleshoot-jaeger/references/troubleshooting.md`. Edit the target,
  preserve the symlink, and inspect the symptom index with `python3
  agent-packages/troubleshoot-jaeger/.apm/skills/troubleshoot-jaeger/scripts/show_cases.py
  agent-packages/troubleshoot-jaeger/.apm/skills/troubleshoot-jaeger/references/troubleshooting.md`.
- Integration suites are designed to run inside the chart's test-runner Pod. For integration behavior, change the
  Robot suites or their image under `integration-tests/`, then rely on `.github/workflows/integration-tests.yml` for the
  full Kind-based installation check rather than assuming a local Robot invocation is equivalent.
- Docker image components are declared separately in `.github/docker-dev-config.json`,
  `.github/docker-build-config.json`, and the matrix in `.github/workflows/build.yml`. When adding, removing, or
  relocating an image build, update every applicable declaration so development, release, and manual builds stay
  aligned.

## Done when

- `go test ./...` passes from `readiness-probe/` when the Go module changes.
- The repository Super-Linter passes for changed source and configuration files.
- `mkdocs build --verbose --strict` passes when documentation or MkDocs configuration changes.
- Chart, image, or integration changes pass the applicable Docker and Kind-based GitHub Actions workflows.
- The final response lists checks run and checks that could not be run.

## Context routing

- Before changing chart values or templates, read `docs/installation.md` and the applicable file under `docs/examples/`
  for the documented installation contract and supported configuration examples.
- Before changing the troubleshooting skill or catalog, read
  `agent-packages/troubleshoot-jaeger/.apm/skills/troubleshoot-jaeger/SKILL.md` for its evidence and safety contract.
