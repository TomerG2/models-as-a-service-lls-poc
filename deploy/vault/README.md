# Vault Secrets Management

This directory provides **example manifests and scripts** for populating the
Kubernetes Secrets that the LlamaStack overlays expect. The examples use
HashiCorp Vault as the secrets source, but any secrets manager (AWS Secrets
Manager, Azure Key Vault, CyberArk, etc.) works as long as the resulting K8s
Secrets match the contract below.

## Secret Contract

Every overlay references secrets by a fixed name and key set. All secrets
**must** be created in the `llm` namespace.

| Provider | K8s Secret Name | Keys | Referenced By |
|---|---|---|---|
| Anthropic | `anthropic-anthropic-api-key` | `api-key` | `overlays/anthropic/patches/deployment-patch.yaml` |
| OpenAI | `openai-openai-api-key` | `api-key` | `overlays/openai/patches/deployment-patch.yaml` |
| Gemini | `gemini-gemini-api-key` | `api-key` | `overlays/gemini/patches/deployment-patch.yaml` |
| Gemini Vertex AI | `gemini-vertex-ai-vertex-ai-credentials` | `project`, `location`, `service-account.json` | `overlays/gemini-vertex-ai/patches/deployment-patch.yaml` |

## Approaches

### Option A: Vault CLI Script (simplest -- no operators needed)

The script at `scripts/create-secrets-from-vault.sh` reads secrets from Vault
with `vault kv get` and creates the corresponding K8s Secrets. You must be
authenticated to Vault before running it (`vault login` or `VAULT_TOKEN`).

```bash
export VAULT_ADDR=https://vault.example.com
# Sync all providers
./scripts/create-secrets-from-vault.sh --all

# Sync a single provider
./scripts/create-secrets-from-vault.sh --provider gemini
```

Or via the Makefile from the `llamastack-integration/` directory:

```bash
make vault-sync-secrets          # all providers
make vault-sync-secret-gemini    # single provider
```

### Option B: External Secrets Operator (enterprise, provider-agnostic)

The `external-secrets/` directory contains example CRDs for the
[External Secrets Operator](https://external-secrets.io/) (ESO). ESO watches
`ExternalSecret` resources and automatically creates/rotates K8s Secrets.

1. Install ESO in your cluster (see ESO docs).
2. Review and adapt `external-secrets/secret-store.yaml` to your Vault setup.
3. Apply the manifests:

```bash
make vault-apply-eso
```

ESO will create the K8s Secrets automatically. The `refreshInterval` is set to
`1m`, so rotated secrets in Vault propagate within a minute.

### Option C: Manual / Existing Pipeline

If you manage secrets through another pipeline, create the secrets directly:

```bash
NAMESPACE=llm

# Anthropic
kubectl create secret generic anthropic-anthropic-api-key \
  --namespace "$NAMESPACE" \
  --from-literal=api-key="$ANTHROPIC_API_KEY"

# OpenAI
kubectl create secret generic openai-openai-api-key \
  --namespace "$NAMESPACE" \
  --from-literal=api-key="$OPENAI_API_KEY"

# Gemini
kubectl create secret generic gemini-gemini-api-key \
  --namespace "$NAMESPACE" \
  --from-literal=api-key="$GEMINI_API_KEY"

# Gemini Vertex AI
kubectl create secret generic gemini-vertex-ai-vertex-ai-credentials \
  --namespace "$NAMESPACE" \
  --from-literal=project="$VERTEX_AI_PROJECT" \
  --from-literal=location="$VERTEX_AI_LOCATION" \
  --from-file=service-account.json="$GOOGLE_APPLICATION_CREDENTIALS"
```

## Verification

Confirm that the required secrets exist and contain the expected keys:

```bash
# Quick status check (via Makefile)
make vault-status

# Or manually
kubectl get secrets -n llm

# Verify a specific secret has the right keys
kubectl get secret anthropic-anthropic-api-key -n llm -o jsonpath='{.data}' | jq 'keys'
```

After secrets are in place, deploy the overlay as usual:

```bash
kubectl apply -k deploy/overlays/gemini
```
