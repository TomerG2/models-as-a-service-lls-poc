#!/bin/bash

# Test script for LlamaStack adapter integration with MaaS
set -e

echo "🔧 Testing LlamaStack Adapter Integration with MaaS"
echo "=================================================="

# Configuration
NAMESPACE=${NAMESPACE:-default}
ADAPTER_SERVICE="llamastack-adapter"
TIMEOUT=${TIMEOUT:-60}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
log_info "Checking prerequisites..."

if ! command -v kubectl &> /dev/null; then
    log_error "kubectl is required but not installed"
    exit 1
fi

if ! command -v curl &> /dev/null; then
    log_error "curl is required but not installed"
    exit 1
fi

# Check if adapter is deployed
log_info "Checking if adapter is deployed..."
if ! kubectl get deployment ${ADAPTER_SERVICE} -n ${NAMESPACE} &> /dev/null; then
    log_error "Adapter deployment not found. Deploy it first with: make deploy"
    exit 1
fi

# Wait for deployment to be ready
log_info "Waiting for adapter deployment to be ready..."
if ! kubectl wait --for=condition=available deployment/${ADAPTER_SERVICE} -n ${NAMESPACE} --timeout=${TIMEOUT}s; then
    log_error "Adapter deployment failed to become ready"
    kubectl describe deployment ${ADAPTER_SERVICE} -n ${NAMESPACE}
    kubectl logs -l app=${ADAPTER_SERVICE} -n ${NAMESPACE} --tail=20
    exit 1
fi

log_info "✅ Adapter deployment is ready"

# Test 1: Health check
log_info "Test 1: Health check..."
kubectl port-forward svc/${ADAPTER_SERVICE} 8080:8080 -n ${NAMESPACE} &
FORWARD_PID=$!
sleep 3

if curl -f -s http://localhost:8080/health > /dev/null; then
    log_info "✅ Health check passed"
else
    log_error "❌ Health check failed"
    kill $FORWARD_PID 2>/dev/null || true
    exit 1
fi

# Test 2: Models endpoint
log_info "Test 2: Models endpoint..."
if MODELS=$(curl -f -s http://localhost:8080/v1/models); then
    log_info "✅ Models endpoint accessible"
    echo "Response: $MODELS" | head -c 200
    echo
else
    log_error "❌ Models endpoint failed"
    kill $FORWARD_PID 2>/dev/null || true
    exit 1
fi

kill $FORWARD_PID 2>/dev/null || true
sleep 1

# Test 3: Check LLMInferenceService
log_info "Test 3: Checking LLMInferenceService integration..."
if kubectl get llmisvc ${ADAPTER_SERVICE} -n ${NAMESPACE} &> /dev/null; then
    log_info "✅ LLMInferenceService found"

    # Check if it has the right annotations
    if kubectl get llmisvc ${ADAPTER_SERVICE} -n ${NAMESPACE} -o yaml | grep -q "opendatahub.io/genai-use-case"; then
        log_info "✅ Proper MaaS annotations found"
    else
        log_warn "⚠️  MaaS annotations not found"
    fi
else
    log_error "❌ LLMInferenceService not found"
    log_info "Apply it with: kubectl apply -f deployment/k8s/llmisvc.yaml"
fi

# Test 4: Check if MaaS can discover this service (if MaaS is available)
log_info "Test 4: Testing MaaS integration (if available)..."
if kubectl get pods -l app=maas-api &> /dev/null; then
    log_info "MaaS detected, testing integration..."

    # This would require a valid MaaS token - skip for now
    log_warn "⚠️  MaaS integration test requires valid token - skipping"
    log_info "To test manually:"
    log_info "1. Get a MaaS token"
    log_info "2. curl -H \"Authorization: Bearer \$TOKEN\" http://maas-api/v1/models"
    log_info "3. Look for llamastack models in the response"
else
    log_info "MaaS not detected in cluster - skipping integration test"
fi

echo
log_info "🎉 Integration tests completed!"
log_info "=================================================="
log_info "Next steps:"
log_info "1. Configure your LlamaStack endpoint in deployment/k8s/configmap.yaml"
log_info "2. Set your API key in deployment/k8s/secret.yaml"
log_info "3. Apply the configuration: kubectl apply -f deployment/k8s/"
log_info "4. Test MaaS integration with a valid token"
echo