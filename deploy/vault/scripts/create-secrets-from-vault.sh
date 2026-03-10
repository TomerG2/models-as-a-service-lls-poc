#!/usr/bin/env bash
#
# create-secrets-from-vault.sh
#
# Reads secrets from HashiCorp Vault and creates the corresponding
# Kubernetes Secrets expected by the LlamaStack overlays.
#
# Prerequisites:
#   - vault CLI installed and authenticated (vault login / VAULT_TOKEN)
#   - kubectl configured for the target cluster
#
# Usage:
#   ./create-secrets-from-vault.sh --all
#   ./create-secrets-from-vault.sh --provider anthropic
#   ./create-secrets-from-vault.sh --provider gemini-vertex-ai

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (override via environment variables)
# ---------------------------------------------------------------------------
: "${VAULT_ADDR:?VAULT_ADDR must be set}"
VAULT_KV_MOUNT="${VAULT_KV_MOUNT:-secret}"
VAULT_PATH_PREFIX="${VAULT_PATH_PREFIX:-llm}"
NAMESPACE="${NAMESPACE:-llm}"

PROVIDERS=(anthropic openai gemini gemini-vertex-ai)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF
Usage: $(basename "$0") [--all | --provider <name>]

Options:
  --all                Sync secrets for all providers
  --provider <name>    Sync secrets for a single provider
                       Valid providers: ${PROVIDERS[*]}

Environment variables:
  VAULT_ADDR           Vault server address (required)
  VAULT_KV_MOUNT       KV engine mount path (default: secret)
  VAULT_PATH_PREFIX    Path prefix for provider secrets (default: llm)
  NAMESPACE            Kubernetes namespace (default: llm)
EOF
  exit 1
}

vault_get_field() {
  local path="$1" field="$2"
  vault kv get -mount="$VAULT_KV_MOUNT" -field="$field" "$path"
}

apply_secret() {
  echo "  applying secret to namespace $NAMESPACE ..."
  kubectl create secret generic "$@" \
    --namespace "$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
}

# ---------------------------------------------------------------------------
# Per-provider sync functions
# ---------------------------------------------------------------------------
sync_anthropic() {
  echo "[anthropic] reading from vault path: ${VAULT_PATH_PREFIX}/anthropic"
  local api_key
  api_key=$(vault_get_field "${VAULT_PATH_PREFIX}/anthropic" "api-key")

  apply_secret anthropic-anthropic-api-key \
    --from-literal=api-key="$api_key"

  echo "[anthropic] done"
}

sync_openai() {
  echo "[openai] reading from vault path: ${VAULT_PATH_PREFIX}/openai"
  local api_key
  api_key=$(vault_get_field "${VAULT_PATH_PREFIX}/openai" "api-key")

  apply_secret openai-openai-api-key \
    --from-literal=api-key="$api_key"

  echo "[openai] done"
}

sync_gemini() {
  echo "[gemini] reading from vault path: ${VAULT_PATH_PREFIX}/gemini"
  local api_key
  api_key=$(vault_get_field "${VAULT_PATH_PREFIX}/gemini" "api-key")

  apply_secret gemini-gemini-api-key \
    --from-literal=api-key="$api_key"

  echo "[gemini] done"
}

sync_gemini_vertex_ai() {
  echo "[gemini-vertex-ai] reading from vault path: ${VAULT_PATH_PREFIX}/gemini-vertex-ai"
  local project location sa_json

  project=$(vault_get_field "${VAULT_PATH_PREFIX}/gemini-vertex-ai" "project")
  location=$(vault_get_field "${VAULT_PATH_PREFIX}/gemini-vertex-ai" "location")
  sa_json=$(vault_get_field "${VAULT_PATH_PREFIX}/gemini-vertex-ai" "service-account.json")

  # Write service account JSON to a temp file for --from-file
  local tmpfile
  tmpfile=$(mktemp)
  trap 'rm -f "$tmpfile"' RETURN
  echo "$sa_json" > "$tmpfile"

  apply_secret gemini-vertex-ai-vertex-ai-credentials \
    --from-literal=project="$project" \
    --from-literal=location="$location" \
    --from-file=service-account.json="$tmpfile"

  echo "[gemini-vertex-ai] done"
}

sync_provider() {
  case "$1" in
    anthropic)        sync_anthropic ;;
    openai)           sync_openai ;;
    gemini)           sync_gemini ;;
    gemini-vertex-ai) sync_gemini_vertex_ai ;;
    *)
      echo "Error: unknown provider '$1'"
      echo "Valid providers: ${PROVIDERS[*]}"
      exit 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
  usage
fi

case "$1" in
  --all)
    echo "Syncing all providers from Vault ($VAULT_ADDR) ..."
    kubectl create namespace "$NAMESPACE" 2>/dev/null || true
    for provider in "${PROVIDERS[@]}"; do
      sync_provider "$provider"
    done
    echo "All providers synced."
    ;;
  --provider)
    [[ -z "${2:-}" ]] && usage
    echo "Syncing provider '$2' from Vault ($VAULT_ADDR) ..."
    kubectl create namespace "$NAMESPACE" 2>/dev/null || true
    sync_provider "$2"
    ;;
  *)
    usage
    ;;
esac
