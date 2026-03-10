# LlamaStack Integration into MaaS — Demo Prep

**Focus:** How LlamaStack is integrated, how API keys flow, how the per-provider instance model works.
**Format:** 15 min walkthrough + live demo

---

## Part 1: Integration Mechanism (5 min)

### LlamaStack runs as a standard `LLMInferenceService`

The same KServe CRD used for local GPU models. MaaS doesn't know or care that it's LlamaStack inside — it discovers it the same way it discovers vLLM or any other model server.

**Base resource** (`deploy/base/llamastack.yaml`):

```yaml
apiVersion: serving.kserve.io/v1alpha1
kind: LLMInferenceService
metadata:
  name: llamastack
spec:
  model:
    uri: hf://sshleifer/tiny-gpt2   # dummy — KServe requires it, LlamaStack ignores it
    name: llamastack-external-models
  router:
    gateway:
      refs:
        - name: maas-default-gateway   # this is what connects it to MaaS
          namespace: openshift-ingress
  template:
    containers:
      - name: main
        image: "llamastack/distribution-starter:latest"
```

**What happens at startup** — the container entrypoint runs an inline script that:
1. Resolves the starter distribution's default config path
2. Patches it with Python to set port 8000 + KServe TLS cert paths
3. Runs `llama stack run` with the patched config

This avoids building a custom Docker image — we use the upstream image unmodified.

### How MaaS discovers it

MaaS API lists all `LLMInferenceService` resources in the cluster, checks which ones reference the MaaS gateway (`spec.router.gateway.refs`), then calls each one's `/v1/models` endpoint. LlamaStack responds with the OpenAI-compatible model list. No special handling — same flow as local models.

---

## Part 2: How the API Key Is Passed (3 min)

Two-step process:

**Step 1 — Kubernetes Secret** (created by the operator):
```bash
export GEMINI_API_KEY="actual-key-here"
kubectl create secret generic gemini-gemini-api-key \
  --from-literal=api-key="$GEMINI_API_KEY" -n llm
```

**Step 2 — Kustomize JSON patch** injects it as an env var into the container:
```yaml
# deploy/overlays/gemini/patches/deployment-patch.yaml (entire file)
- op: add
  path: /spec/template/containers/0/env/-
  value:
    name: GEMINI_API_KEY
    valueFrom:
      secretKeyRef:
        name: gemini-gemini-api-key
        key: api-key
- op: replace
  path: /spec/model/name
  value: gemini-2.0-flash
```

LlamaStack's starter distribution auto-discovers providers based on which API key env vars are set. If `GEMINI_API_KEY` is present, it enables Gemini. If `OPENAI_API_KEY` is present, it enables OpenAI. No explicit provider config file needed.

The key never appears in any YAML file committed to git — it's injected from the environment at secret creation time.

---

## Part 3: One Instance Per Provider + API Key (5 min)

### The model

Each provider (or provider + API key combination) gets its own LlamaStack pod:

```
gemini-llamastack    pod  ──► Gemini API (key A)
openai-llamastack    pod  ──► OpenAI API (key B)
anthropic-llamastack pod  ──► Anthropic API (key C)
```

### How Kustomize makes this work

All providers share the same base template. Each overlay applies:
- `namePrefix: gemini-` — renames `llamastack` → `gemini-llamastack`
- `namespace: llm`
- `labels: provider: gemini`
- The JSON patch above (API key + model name)

```
deploy/
├── base/llamastack.yaml              ← one shared template
└── overlays/
    ├── gemini/kustomization.yaml      ← namePrefix: gemini-
    ├── openai/kustomization.yaml      ← namePrefix: openai-
    └── anthropic/kustomization.yaml   ← namePrefix: anthropic-
```

Deploying all three:
```bash
kubectl apply -k deploy/overlays/gemini
kubectl apply -k deploy/overlays/openai
kubectl apply -k deploy/overlays/anthropic
```

### Why one-per-provider rather than a single multi-provider instance

- **Independent lifecycle** — deploy/update/delete Gemini without touching OpenAI
- **Fault isolation** — expired API key on one provider doesn't affect others
- **Per-provider policies** — each `LLMInferenceService` can have its own rate limits, tier restrictions, and routing rules
- **Scales to multiple keys per provider** — a second Gemini API key for a different team is just another overlay with a different `namePrefix` (e.g., `gemini-team-b-`)

### Multiple keys for the same provider

Same pattern — create another overlay:
```
overlays/
├── gemini/                  ← team A's Gemini key
├── gemini-team-b/           ← team B's Gemini key (different namePrefix, different secret)
└── openai/
```

Each gets its own pod, its own `LLMInferenceService`, its own rate limits.

---

## Part 4: Live Demo

### Show deployed resources
```bash
kubectl get llminferenceservice -n llm
kubectl get pods -n llm -l provider=gemini
```

### Authenticate
```bash
OC_TOKEN=$(oc whoami -t)
MAAS_URL="http://maas.apps.ai-dev02.kni.syseng.devcluster.openshift.com"

TOKEN=$(curl -s -k -H "Authorization: Bearer $OC_TOKEN" \
  --json '{"expiration": "1h"}' \
  "$MAAS_URL/maas-api/v1/tokens" | jq -r .token)
```

### Discover models (remote models appear alongside local ones)
```bash
curl -s -k -H "Authorization: Bearer $TOKEN" \
  "$MAAS_URL/maas-api/v1/models" | jq '.data[] | {id, owned_by, ready}'
```

### Send a chat completion through MaaS
```bash
curl -s -k -X POST \
  "$MAAS_URL/llm/gemini-llamastack/v1/chat/completions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemini/models/gemini-2.5-flash",
    "messages": [{"role": "user", "content": "What is Kubernetes in one sentence?"}],
    "max_tokens": 50
  }' | jq '{model, response: .choices[0].message.content, tokens: .usage}'
```

---

## Anticipated Questions

**Q: Can we control which models LlamaStack exposes?**
Currently the starter distribution exposes all models the API key has access to. Can be narrowed with an explicit LlamaStack config instead of auto-discovery.

**Q: Does LlamaStack add latency?**
A few milliseconds of in-cluster proxying. Negligible compared to the external API call.

**Q: What changes were needed in MaaS code?**
None. LlamaStack deploys as a standard `LLMInferenceService` — MaaS discovers it automatically.

**Q: How would we add a fourth provider (e.g., Bedrock)?**
Create `deploy/overlays/bedrock/` with a kustomization.yaml (namePrefix + labels) and a patch that injects `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`. Deploy with `kubectl apply -k`.
