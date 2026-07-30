# Agent instructions

## Repository
- Purpose: This repository provides Helm charts for deploying Qubership Jaeger on Kubernetes and OpenShift.
- Main paths: `charts/qubership-jaeger/` for the Helm chart; `readiness-probe/` for the Go health checker; `integration-tests/robot/` for Robot Framework suites.
- Read `docs/README.md` for the documentation layout, local preview, and build instructions.

## Commands
- Fast check: `docker run -e RUN_LOCAL=true -e DEFAULT_BRANCH=$(git rev-parse --abbrev-ref HEAD) --env-file .github/super-linter.env -v ${PWD}:/tmp/lint --rm ghcr.io/super-linter/super-linter:slim-$(sed -nE 's#.*uses:\s+super-linter/super-linter/slim@([^\s]+).*#\1#p' .github/workflows/super-linter.yaml)`.
- Documentation setup: `python -m venv venv && source venv/bin/activate && pip install -r requirements_mkdocs.txt`.
- Documentation build: `mkdocs build --clean`.

## Change boundaries
- Follow `integration-tests/README.md` when changing live-cluster Robot suites or integration-test values.
- Follow `docs/installation.md` when changing chart configuration documented for users.

## Updating Key Conventions
- If a user corrects a mistake that could recur in this repository, propose the smallest complete instruction.
- Add the exact approved instruction; omit task-specific, personal, sensitive, duplicate, or tool-enforced guidance.

## Key Conventions
- No key conventions recorded yet.
