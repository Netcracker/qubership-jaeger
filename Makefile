SHELL := /bin/bash

# Directory used for locally installed tooling.
LOCALBIN ?= $(CURDIR)/bin

# Always run the repository-local binary: generated output must not depend on
# whatever helm-docs happens to sit on the developer's or the runner's PATH.
HELM_DOCS ?= $(LOCALBIN)/helm-docs
HELM_DOCS_VERSION ?= v1.14.2
# Records the version of the binary in $(LOCALBIN), so a bumped pin triggers a reinstall.
HELM_DOCS_STAMP := $(LOCALBIN)/.helm-docs-version

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
helm-docs: $(LOCALBIN) ## Install the pinned helm-docs into ./bin unless that exact version is already there.
	@if [ ! -x "$(HELM_DOCS)" ] || [ "$$(cat $(HELM_DOCS_STAMP) 2>/dev/null)" != "$(HELM_DOCS_VERSION)" ]; then \
		echo "installing helm-docs $(HELM_DOCS_VERSION) into $(LOCALBIN)"; \
		GOBIN=$(LOCALBIN) go install github.com/norwoodj/helm-docs/cmd/helm-docs@$(HELM_DOCS_VERSION); \
		echo "$(HELM_DOCS_VERSION)" > $(HELM_DOCS_STAMP); \
	fi

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
