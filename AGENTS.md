## Cursor Cloud specific instructions

### Project overview

This is a **Helm chart project** (not a web application). It deploys a production-ready Jaeger distributed tracing stack on Kubernetes. There is no local "app" to start—development work centers on the Helm chart templates, a Go readiness-probe sidecar, and Robot Framework integration tests that run on K8s.

### Key components

| Component | Path | Language | Notes |
|---|---|---|---|
| Helm chart | `charts/qubership-jaeger/` | YAML/Go templates | Main deliverable |
| Readiness probe | `readiness-probe/` | Go 1.25 | Sidecar binary; has unit tests |
| Integration tests | `integration-tests/` | Python/Robot Framework | Run on K8s clusters, not locally |
| Docker transfer | `docker-transfer/` | Dockerfile | Packaging image |

### Development commands

**Go readiness-probe (build & test):**
```bash
cd readiness-probe && go test -v ./...
cd readiness-probe && go build -o /tmp/readiness-probe .
```

**Helm chart (lint & template):**
```bash
helm lint charts/qubership-jaeger/
helm template test-release charts/qubership-jaeger/
```

**Super-linter (requires Docker):**
```bash
docker run \
  -e RUN_LOCAL=true \
  -e DEFAULT_BRANCH=$(git rev-parse --abbrev-ref HEAD) \
  --env-file .github/super-linter.env \
  -v ${PWD}:/tmp/lint \
  --rm \
  ghcr.io/super-linter/super-linter:slim-v8.3.2
```

**Docker image build (readiness probe):**
```bash
docker build -f readiness-probe/Dockerfile -t jaeger-readiness-probe:dev readiness-probe/
```

### Gotchas

- The Go module requires **Go 1.25+** (`readiness-probe/go.mod`). The system default Go may be older; use `/usr/local/go/bin/go` if installed manually.
- The Dockerfile references `golang:1.26.0-alpine3.22` for the builder stage; local Go version only needs to match `go.mod` (1.25.0).
- Integration tests (`integration-tests/robot/`) are designed to run **inside a Kubernetes cluster** via Helm install, not locally. There are no local Robot Framework test runners.
- Super-linter has some **pre-existing lint findings** (EDITORCONFIG, GITLEAKS, MARKDOWN, PYTHON_*) in the repository. The critical linters (GO, YAML, DOCKERFILE_HADOLINT, CHECKOV, JSON) pass clean.
- Docker daemon needs fuse-overlayfs storage driver and iptables-legacy in this VM environment (nested Docker-in-Docker).
