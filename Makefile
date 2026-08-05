SHELL := /bin/bash

# Directory used for locally installed tooling.
LOCALBIN ?= $(CURDIR)/bin

HELM_DOCS ?= $(shell command -v helm-docs 2>/dev/null || echo $(LOCALBIN)/helm-docs)
HELM_DOCS_VERSION ?= v1.14.2

CHART_DIR ?= charts/qubership-jaeger
# Generated documentation, relative to the repository root.
DOCS_FILE ?= $(CHART_DIR)/README.md

.PHONY: help
help: ## Show this help.
	@grep -hE '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

$(LOCALBIN):
	@mkdir -p $(LOCALBIN)

.PHONY: helm-docs
helm-docs: ## Install helm-docs into ./bin if it is not available yet.
ifeq (,$(shell command -v helm-docs 2>/dev/null))
	@if [ ! -x "$(LOCALBIN)/helm-docs" ]; then \
		echo "helm-docs not found, installing $(HELM_DOCS_VERSION) into $(LOCALBIN)"; \
		mkdir -p $(LOCALBIN); \
		GOBIN=$(LOCALBIN) go install github.com/norwoodj/helm-docs/cmd/helm-docs@$(HELM_DOCS_VERSION); \
	fi
else
	@echo "using helm-docs from $(shell command -v helm-docs)"
endif

.PHONY: docs
docs: helm-docs ## Generate the chart README.md from the chart values.yaml.
	$(HELM_DOCS) --chart-search-root=$(CHART_DIR)
	@echo "generated $(DOCS_FILE)"

.PHONY: docs-check
docs-check: docs ## Fail if the generated documentation is out of date.
	@if [ -n "$$(git status --porcelain -- $(DOCS_FILE))" ]; then \
		echo "$(DOCS_FILE) is out of date, run 'make docs' and commit the result"; \
		git --no-pager diff -- $(DOCS_FILE); \
		exit 1; \
	fi
	@echo "$(DOCS_FILE) is up to date"
