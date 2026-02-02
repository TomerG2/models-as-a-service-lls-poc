# MaaS LlamaStack Adapter

A proof-of-concept adapter service that integrates external LlamaStack instances with the [Models as a Service (MaaS)](https://github.com/opendatahub-io/models-as-a-service) platform.

## Overview

This adapter service acts as a bridge between MaaS and external LlamaStack deployments, enabling:

- **Automatic Model Discovery**: External LlamaStack models appear in MaaS model listings
- **OpenAI-Compatible API**: Maintains OpenAI API compatibility for seamless integration
- **Kubernetes-Native**: Deploys alongside MaaS using standard Kubernetes resources
- **Authentication Integration**: Supports MaaS token-based authentication
- **Health Monitoring**: Includes health checks for Kubernetes probes

## Architecture

```
MaaS Discovery System
        ↓
LLMInferenceService CRD
        ↓
LlamaStack Adapter Service
        ↓
External LlamaStack Instance
```

The adapter service exposes an OpenAI-compatible `/v1/models` endpoint that MaaS can discover through the standard KServe LLMInferenceService mechanism.

## Prerequisites

- Kubernetes cluster with MaaS installed
- Access to a LlamaStack instance
- Docker for building the adapter image
- kubectl configured for your cluster

## Quick Start

### 1. Configure LlamaStack Connection

Edit the configuration files:

```bash
# Update the LlamaStack endpoint
vim deployment/k8s/configmap.yaml

# Set your LlamaStack API key
vim deployment/k8s/secret.yaml
```

### 2. Build and Deploy

```bash
# Build the adapter image
make build

# Deploy to Kubernetes
make deploy
```

### 3. Verify Integration

```bash
# Check if the adapter is running
kubectl get pods -l app=llamastack-adapter

# Test the adapter directly
kubectl port-forward svc/llamastack-adapter 8080:8080
curl http://localhost:8080/v1/models

# Verify MaaS can discover the models
# (Use your MaaS API endpoint and token)
curl -H "Authorization: Bearer $MAAS_TOKEN" \
     http://your-maas-api/v1/models
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LLAMASTACK_ENDPOINT` | LlamaStack base URL | Required |
| `LLAMASTACK_API_KEY` | LlamaStack API key | Optional |
| `ADAPTER_PORT` | Adapter service port | `8080` |
| `ENABLE_AUTH` | Enable token authentication | `true` |
| `LOG_LEVEL` | Log level (debug, info, warn, error) | `info` |
| `LOG_JSON` | JSON log format | `false` |

### Kubernetes Resources

The adapter creates these resources:

- **Deployment**: Runs the adapter service pods
- **Service**: Exposes the adapter within the cluster
- **ConfigMap**: Stores LlamaStack configuration
- **Secret**: Stores LlamaStack credentials
- **LLMInferenceService**: Registers with MaaS discovery

## API Endpoints

### OpenAI-Compatible

- `GET /v1/models` - List available models (OpenAI format)

### Health & Monitoring

- `GET /health` - Detailed health check including LlamaStack connectivity
- `GET /ready` - Kubernetes readiness probe
- `GET /live` - Kubernetes liveness probe

### Example Response

```json
{
  "object": "list",
  "data": [
    {
      "id": "llama-3.1-8b-instruct",
      "object": "model",
      "created": 1704067200,
      "owned_by": "llamastack"
    }
  ]
}
```

## Development

### Prerequisites

- Go 1.25+
- Docker
- kubectl

### Local Development

```bash
# Run locally with environment variables
export LLAMASTACK_ENDPOINT="https://your-llamastack.example.com"
export LLAMASTACK_API_KEY="your-api-key"
export ENABLE_AUTH="false"
export LOG_LEVEL="debug"

go run cmd/adapter/main.go
```

### Building

```bash
# Build binary
make build-local

# Build Docker image
make build-image

# Build and push to registry
make push IMAGE_REGISTRY="your-registry.com"
```

### Testing

```bash
# Run unit tests
go test ./...

# Test against running LlamaStack
make test-integration
```

## Integration with MaaS

### Automatic Discovery

Once deployed, the adapter integrates with MaaS through:

1. **LLMInferenceService CRD**: Registers the adapter with MaaS discovery
2. **Gateway Configuration**: Routes traffic through MaaS gateway
3. **OpenAI Compatibility**: MaaS calls `/v1/models` endpoint
4. **Authentication**: Validates MaaS ServiceAccount tokens

### Model Metadata

Models from LlamaStack are enriched with metadata from the LLMInferenceService annotations:

```yaml
metadata:
  annotations:
    opendatahub.io/genai-use-case: "external-llm"
    openshift.io/description: "LlamaStack external LLM integration"
    openshift.io/display-name: "LlamaStack Models"
```

## Troubleshooting

### Common Issues

**Adapter pods not starting**
```bash
kubectl logs -l app=llamastack-adapter
kubectl describe pod -l app=llamastack-adapter
```

**LlamaStack connectivity issues**
```bash
kubectl exec -it deployment/llamastack-adapter -- wget -qO- http://localhost:8080/health
```

**MaaS not discovering models**
```bash
# Check LLMInferenceService status
kubectl get llmisvc llamastack-adapter -o yaml

# Verify gateway configuration
kubectl get httproute -A | grep llamastack
```

### Debug Mode

Enable debug logging:

```bash
kubectl patch deployment llamastack-adapter -p '{"spec":{"template":{"spec":{"containers":[{"name":"adapter","env":[{"name":"LOG_LEVEL","value":"debug"}]}]}}}}'
```

## Security Considerations

- API keys are stored in Kubernetes Secrets
- Pods run as non-root user (UID 1001)
- Network policies can restrict traffic flow
- TLS should be configured for production deployments

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.