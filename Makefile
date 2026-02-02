.PHONY: help build build-local build-image push deploy undeploy test test-integration lint clean

# Configuration
IMAGE_NAME ?= llamastack-adapter
IMAGE_TAG ?= latest
IMAGE_REGISTRY ?= localhost:5000
FULL_IMAGE_NAME = $(IMAGE_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

# Kubernetes configuration
NAMESPACE ?= default
KUSTOMIZE_DIR = deployment/k8s

help: ## Display this help message
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

build-local: ## Build the Go binary locally
	@echo "Building Go binary..."
	CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o bin/adapter ./cmd/adapter

build-image: ## Build Docker image
	@echo "Building Docker image: $(FULL_IMAGE_NAME)"
	docker build -t $(FULL_IMAGE_NAME) .
	docker tag $(FULL_IMAGE_NAME) $(IMAGE_NAME):latest

build: build-local build-image ## Build both local binary and Docker image

push: build-image ## Build and push Docker image to registry
	@echo "Pushing image: $(FULL_IMAGE_NAME)"
	docker push $(FULL_IMAGE_NAME)

deploy: ## Deploy to Kubernetes
	@echo "Deploying to Kubernetes namespace: $(NAMESPACE)"
	@if [ "$(NAMESPACE)" != "default" ]; then \
		kubectl create namespace $(NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -; \
	fi
	@# Update image in deployment
	@sed 's|image: llamastack-adapter:latest|image: $(FULL_IMAGE_NAME)|g' $(KUSTOMIZE_DIR)/deployment.yaml | \
		sed 's|namespace: default|namespace: $(NAMESPACE)|g' | \
		kubectl apply -f -
	@# Apply other manifests
	@for file in $(KUSTOMIZE_DIR)/*.yaml; do \
		if [ "$$(basename $$file)" != "deployment.yaml" ]; then \
			sed 's|namespace: default|namespace: $(NAMESPACE)|g' $$file | kubectl apply -f -; \
		fi; \
	done
	@echo "Deployment complete! Check status with: kubectl get pods -n $(NAMESPACE) -l app=llamastack-adapter"

undeploy: ## Remove deployment from Kubernetes
	@echo "Removing deployment from namespace: $(NAMESPACE)"
	@kubectl delete -f $(KUSTOMIZE_DIR)/ --ignore-not-found=true -n $(NAMESPACE)

test: ## Run unit tests
	@echo "Running unit tests..."
	go test -v ./...

test-integration: ## Run integration tests (requires running service)
	@echo "Running integration tests..."
	@echo "Testing health endpoint..."
	@curl -f http://localhost:8080/health || (echo "Health check failed - is the service running?" && exit 1)
	@echo "Testing models endpoint..."
	@curl -f http://localhost:8080/v1/models || (echo "Models endpoint failed" && exit 1)
	@echo "Integration tests passed!"

lint: ## Run linters
	@echo "Running linters..."
	@which golangci-lint >/dev/null 2>&1 || (echo "Installing golangci-lint..." && go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest)
	golangci-lint run ./...

fmt: ## Format Go code
	@echo "Formatting Go code..."
	go fmt ./...
	goimports -w .

clean: ## Clean build artifacts
	@echo "Cleaning build artifacts..."
	rm -rf bin/
	docker rmi $(FULL_IMAGE_NAME) $(IMAGE_NAME):latest 2>/dev/null || true

# Development helpers
dev-setup: ## Set up development environment
	@echo "Setting up development environment..."
	go mod download
	@echo "Install development tools..."
	go install golang.org/x/tools/cmd/goimports@latest

dev-run: ## Run service locally for development
	@echo "Starting service locally..."
	@echo "Make sure to set LLAMASTACK_ENDPOINT environment variable"
	go run ./cmd/adapter

# Kubernetes helpers
k8s-logs: ## Show logs from running pods
	kubectl logs -l app=llamastack-adapter -n $(NAMESPACE) --tail=100

k8s-status: ## Show Kubernetes deployment status
	kubectl get pods,svc,llmisvc -l app=llamastack-adapter -n $(NAMESPACE)

k8s-debug: ## Debug Kubernetes deployment
	@echo "=== Pod Status ==="
	kubectl describe pods -l app=llamastack-adapter -n $(NAMESPACE)
	@echo "=== Service Status ==="
	kubectl describe svc llamastack-adapter -n $(NAMESPACE)
	@echo "=== LLMInferenceService Status ==="
	kubectl describe llmisvc llamastack-adapter -n $(NAMESPACE)

k8s-port-forward: ## Port forward to test locally
	@echo "Port forwarding to localhost:8080..."
	kubectl port-forward svc/llamastack-adapter 8080:8080 -n $(NAMESPACE)

# Utility targets
check-env: ## Check required environment variables
	@echo "Checking environment variables..."
	@echo "LLAMASTACK_ENDPOINT: $${LLAMASTACK_ENDPOINT:-NOT SET}"
	@echo "LLAMASTACK_API_KEY: $${LLAMASTACK_API_KEY:+SET}$${LLAMASTACK_API_KEY:-NOT SET}"
	@echo "IMAGE_REGISTRY: $(IMAGE_REGISTRY)"
	@echo "NAMESPACE: $(NAMESPACE)"

version: ## Show version information
	@echo "Go version: $$(go version)"
	@echo "Docker version: $$(docker --version 2>/dev/null || echo 'Not installed')"
	@echo "kubectl version: $$(kubectl version --client --short 2>/dev/null || echo 'Not configured')"