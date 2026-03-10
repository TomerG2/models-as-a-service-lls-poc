PROJECT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
VAULT_DIR   := $(PROJECT_DIR)/deploy/vault

# ---------------------------------------------------------------------------
# Configurable variables (override via environment or command line)
# ---------------------------------------------------------------------------
NAMESPACE        ?= llm
VAULT_KV_MOUNT   ?= secret
VAULT_PATH_PREFIX ?= llm

# Vault address -- no default; must be set for vault-sync targets.
# VAULT_ADDR ?=

# ---------------------------------------------------------------------------
# Provider list
# ---------------------------------------------------------------------------
PROVIDERS := anthropic openai gemini gemini-vertex-ai

SECRET_NAMES := \
  anthropic-anthropic-api-key \
  openai-openai-api-key \
  gemini-gemini-api-key \
  gemini-vertex-ai-vertex-ai-credentials

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
.PHONY: help
help: ## Show this help message
	@echo "LlamaStack Integration -- Vault Secrets Makefile"
	@echo ""
	@echo "Usage: make <target> [VAULT_ADDR=... NAMESPACE=...]"
	@echo ""
	@echo "Targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-30s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Per-provider targets (generated):"
	@$(foreach p,$(PROVIDERS),echo "  vault-sync-secret-$(p)";)
	@echo ""
	@echo "Variables:"
	@echo "  VAULT_ADDR           Vault server address (required for sync)"
	@echo "  VAULT_KV_MOUNT       KV mount path (default: secret)"
	@echo "  VAULT_PATH_PREFIX    Path prefix in Vault (default: llm)"
	@echo "  NAMESPACE            K8s namespace (default: llm)"

.DEFAULT_GOAL := help

# ---------------------------------------------------------------------------
# Vault CLI -- sync secrets from Vault to K8s
# ---------------------------------------------------------------------------
.PHONY: vault-sync-secrets
vault-sync-secrets: ## Sync all provider secrets from Vault to K8s
	VAULT_KV_MOUNT=$(VAULT_KV_MOUNT) \
	VAULT_PATH_PREFIX=$(VAULT_PATH_PREFIX) \
	NAMESPACE=$(NAMESPACE) \
	$(VAULT_DIR)/scripts/create-secrets-from-vault.sh --all

# Dynamic per-provider targets: make vault-sync-secret-gemini, etc.
define provider_target
.PHONY: vault-sync-secret-$(1)
vault-sync-secret-$(1): ## Sync $(1) secret from Vault to K8s
	VAULT_KV_MOUNT=$(VAULT_KV_MOUNT) \
	VAULT_PATH_PREFIX=$(VAULT_PATH_PREFIX) \
	NAMESPACE=$(NAMESPACE) \
	$(VAULT_DIR)/scripts/create-secrets-from-vault.sh --provider $(1)
endef
$(foreach p,$(PROVIDERS),$(eval $(call provider_target,$(p))))

# ---------------------------------------------------------------------------
# External Secrets Operator
# ---------------------------------------------------------------------------
.PHONY: vault-apply-eso
vault-apply-eso: ## Apply ESO SecretStore and ExternalSecret manifests
	kubectl apply -f $(VAULT_DIR)/external-secrets/

.PHONY: vault-clean-eso
vault-clean-eso: ## Remove all ESO manifests
	kubectl delete -f $(VAULT_DIR)/external-secrets/ --ignore-not-found

# ---------------------------------------------------------------------------
# Status & cleanup
# ---------------------------------------------------------------------------
.PHONY: vault-status
vault-status: ## Show which required secrets exist in the cluster
	@echo "Checking secrets in namespace $(NAMESPACE) ..."
	@for secret in $(SECRET_NAMES); do \
		if kubectl get secret "$$secret" -n $(NAMESPACE) >/dev/null 2>&1; then \
			echo "  [OK]      $$secret"; \
		else \
			echo "  [MISSING] $$secret"; \
		fi; \
	done

.PHONY: vault-clean-secrets
vault-clean-secrets: ## Delete all provider K8s Secrets
	@echo "Deleting provider secrets from namespace $(NAMESPACE) ..."
	@for secret in $(SECRET_NAMES); do \
		kubectl delete secret "$$secret" -n $(NAMESPACE) --ignore-not-found; \
	done
