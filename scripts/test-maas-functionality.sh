#!/bin/bash
#
# test-maas-functionality.sh - Test MaaS (Models-as-a-Service) functionality
#
# This script tests the core MaaS platform functionality including:
# - Authentication (token generation)
# - Models API (discovery)
# - Model inference (chat completions)
#
# Prerequisites:
# - oc CLI tool configured and logged in
# - jq tool for JSON processing
# - MaaS platform deployed and operational
#
# Usage:
#   ./test-maas-functionality.sh [MODEL_NAME]
#
# Examples:
#   ./test-maas-functionality.sh                           # Test with default model
#   ./test-maas-functionality.sh facebook/opt-125m        # Test with specific model
#

set -e

# Configuration
DEFAULT_MODEL="facebook/opt-125m"
DEFAULT_MODEL_ENDPOINT="/llm/facebook-opt-125m-simulated/v1/chat/completions"
TOKEN_EXPIRATION="10m"
MAX_TOKENS=20

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    if ! command -v oc &> /dev/null; then
        log_error "oc CLI tool is required but not installed"
        exit 1
    fi

    if ! command -v jq &> /dev/null; then
        log_error "jq tool is required but not installed"
        exit 1
    fi

    if ! oc whoami &> /dev/null; then
        log_error "Not logged in to OpenShift cluster. Please run 'oc login' first"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Get cluster information
get_cluster_info() {
    log_info "Detecting cluster information..."

    CLUSTER_DOMAIN=$(kubectl get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null || echo "")
    if [[ -z "$CLUSTER_DOMAIN" ]]; then
        log_error "Failed to detect cluster domain"
        exit 1
    fi

    MAAS_BASE_URL="https://maas.${CLUSTER_DOMAIN}"
    log_info "MaaS Base URL: ${MAAS_BASE_URL}"
}

# Test authentication
test_authentication() {
    log_info "Testing MaaS authentication..."

    TOKEN_RESPONSE=$(curl -sSk -H "Authorization: Bearer $(oc whoami -t)" \
        --json "{\"expiration\": \"${TOKEN_EXPIRATION}\"}" \
        "${MAAS_BASE_URL}/maas-api/v1/tokens" 2>/dev/null || echo "")

    if [[ -z "$TOKEN_RESPONSE" ]]; then
        log_error "Failed to connect to MaaS API"
        return 1
    fi

    TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.token' 2>/dev/null || echo "null")

    if [[ "$TOKEN" == "null" || -z "$TOKEN" ]]; then
        log_error "Authentication failed"
        echo "Response: $TOKEN_RESPONSE"
        return 1
    fi

    log_success "Authentication successful"
    log_info "Token (first 20 chars): ${TOKEN:0:20}..."
    return 0
}

# Test models API
test_models_api() {
    log_info "Testing models discovery API..."

    MODELS=$(curl -sSk "${MAAS_BASE_URL}/maas-api/v1/models" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $TOKEN" 2>/dev/null || echo "")

    if [[ -z "$MODELS" ]]; then
        log_error "Failed to query models API"
        return 1
    fi

    MODEL_COUNT=$(echo "$MODELS" | jq -r '.data | length' 2>/dev/null || echo "0")

    if [[ "$MODEL_COUNT" -gt 0 ]]; then
        log_success "Models API working - found $MODEL_COUNT model(s)"
        echo "$MODELS" | jq .
    else
        log_warning "Models API accessible but no models discovered"
        echo "Response: $MODELS"
    fi

    return 0
}

# Test model inference
test_model_inference() {
    local model_name="${1:-$DEFAULT_MODEL}"
    local model_endpoint="${2:-$DEFAULT_MODEL_ENDPOINT}"

    log_info "Testing model inference..."
    log_info "Model: $model_name"
    log_info "Endpoint: ${MAAS_BASE_URL}${model_endpoint}"

    MODEL_RESPONSE=$(curl -sSk -w "\n%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"${model_name}\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}], \"max_tokens\": ${MAX_TOKENS}}" \
        "${MAAS_BASE_URL}${model_endpoint}" 2>/dev/null || echo "000")

    HTTP_CODE=$(echo "$MODEL_RESPONSE" | tail -n1)
    RESPONSE_BODY=$(echo "$MODEL_RESPONSE" | sed '$d')

    log_info "HTTP Status Code: $HTTP_CODE"

    if [[ "$HTTP_CODE" == "200" ]]; then
        log_success "Model inference working!"

        CONTENT=$(echo "$RESPONSE_BODY" | jq -r '.choices[0].message.content' 2>/dev/null || echo "")
        if [[ -n "$CONTENT" && "$CONTENT" != "null" ]]; then
            echo "Model Response: $CONTENT"
        else
            echo "Full Response: $RESPONSE_BODY"
        fi
    else
        log_error "Model inference failed"
        echo "Response: $RESPONSE_BODY"
        return 1
    fi

    return 0
}

# Main function
main() {
    local model_name="${1:-}"

    echo "========================================="
    echo "🚀 MaaS Platform Functionality Test"
    echo "========================================="
    echo ""

    check_prerequisites
    echo ""

    get_cluster_info
    echo ""

    if ! test_authentication; then
        log_error "Authentication test failed - cannot continue"
        exit 1
    fi
    echo ""

    test_models_api
    echo ""

    if [[ -n "$model_name" ]]; then
        # Custom model - user needs to provide endpoint
        read -p "Enter model endpoint path (e.g., /llm/model-name/v1/chat/completions): " model_endpoint
        test_model_inference "$model_name" "$model_endpoint"
    else
        # Use default model
        test_model_inference
    fi

    echo ""
    echo "========================================="
    log_success "MaaS functionality test completed!"
    echo "========================================="
}

# Show help
show_help() {
    cat << EOF
test-maas-functionality.sh - Test MaaS platform functionality

Usage: $0 [OPTIONS] [MODEL_NAME]

Arguments:
  MODEL_NAME              Optional model name to test (default: facebook/opt-125m)

Options:
  -h, --help             Show this help message and exit

Examples:
  $0                                    # Test with default model
  $0 facebook/opt-125m                 # Test with specific model

Environment Variables:
  TOKEN_EXPIRATION       Token expiration time (default: 10m)
  MAX_TOKENS            Max tokens for model response (default: 20)

Prerequisites:
  - oc CLI tool installed and logged in
  - jq tool installed
  - MaaS platform deployed and accessible

EOF
}

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac