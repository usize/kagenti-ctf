# Leaked Access Token CTF Demo — Build System
#
# Builds document-service and opa-service from zero-trust-agent-demo source,
# plus the claude-agent image from this demo's Dockerfile.

ZERO_TRUST_DIR ?= $(shell cd ../../../zero-trust-agent-demo 2>/dev/null && pwd || echo "$(HOME)/Workspace/ctf/zero-trust-agent-demo")
KIND_CLUSTER   ?= kagenti
REGISTRY       ?= ctf
CONTAINER_ENGINE ?= docker

# Image names
DOCUMENT_SERVICE_IMAGE := $(REGISTRY)/document-service:latest
OPA_SERVICE_IMAGE      := $(REGISTRY)/opa-service:latest
CLAUDE_AGENT_IMAGE     := $(REGISTRY)/claude-agent:latest

.PHONY: build build-document-service build-opa-service build-claude-agent
.PHONY: load push clean check-deps

## help: Show this help message
help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Build targets:"
	@echo "  build                  Build all images locally"
	@echo "  build-document-service Build document-service from zero-trust-agent-demo"
	@echo "  build-opa-service      Build opa-service from zero-trust-agent-demo"
	@echo "  build-claude-agent     Build claude-agent image"
	@echo ""
	@echo "Cluster targets:"
	@echo "  load                   Load all images into Kind cluster"
	@echo "  push                   Push all images to registry (set REGISTRY=)"
	@echo ""
	@echo "Utilities:"
	@echo "  check-deps             Verify required tools are installed"
	@echo "  clean                  Remove built images"
	@echo ""
	@echo "Variables:"
	@echo "  ZERO_TRUST_DIR=$(ZERO_TRUST_DIR)"
	@echo "  KIND_CLUSTER=$(KIND_CLUSTER)"
	@echo "  REGISTRY=$(REGISTRY)"
	@echo "  CONTAINER_ENGINE=$(CONTAINER_ENGINE)"

## check-deps: Verify required tools are installed
check-deps:
	@command -v $(CONTAINER_ENGINE) >/dev/null 2>&1 || { echo "ERROR: $(CONTAINER_ENGINE) not found"; exit 1; }
	@command -v kind >/dev/null 2>&1 || { echo "ERROR: kind not found"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not found"; exit 1; }
	@test -d "$(ZERO_TRUST_DIR)" || { echo "ERROR: zero-trust-agent-demo not found at $(ZERO_TRUST_DIR)"; exit 1; }
	@echo "All dependencies found."

## build: Build all container images
build: build-document-service build-opa-service build-claude-agent
	@echo "All images built successfully."

## build-document-service: Build document-service from zero-trust-agent-demo source
build-document-service: check-deps
	@echo "Building document-service..."
	$(CONTAINER_ENGINE) build \
		-t $(DOCUMENT_SERVICE_IMAGE) \
		-f $(ZERO_TRUST_DIR)/document-service/Dockerfile \
		$(ZERO_TRUST_DIR)

## build-opa-service: Build opa-service from zero-trust-agent-demo source
build-opa-service: check-deps
	@echo "Building opa-service..."
	$(CONTAINER_ENGINE) build \
		-t $(OPA_SERVICE_IMAGE) \
		-f $(ZERO_TRUST_DIR)/opa-service/Dockerfile \
		$(ZERO_TRUST_DIR)

## build-claude-agent: Build the claude-agent image
build-claude-agent: check-deps
	@echo "Building claude-agent..."
	$(CONTAINER_ENGINE) build \
		-t $(CLAUDE_AGENT_IMAGE) \
		-f images/claude-agent/Dockerfile \
		images/claude-agent/

## load: Load all images into the Kind cluster
load: check-deps
	@echo "Loading images into Kind cluster '$(KIND_CLUSTER)'..."
	kind load docker-image $(DOCUMENT_SERVICE_IMAGE) --name $(KIND_CLUSTER)
	kind load docker-image $(OPA_SERVICE_IMAGE) --name $(KIND_CLUSTER)
	kind load docker-image $(CLAUDE_AGENT_IMAGE) --name $(KIND_CLUSTER)
	@echo "All images loaded."

## push: Push all images to a remote registry
push: check-deps
	@echo "Pushing images to $(REGISTRY)..."
	$(CONTAINER_ENGINE) push $(DOCUMENT_SERVICE_IMAGE)
	$(CONTAINER_ENGINE) push $(OPA_SERVICE_IMAGE)
	$(CONTAINER_ENGINE) push $(CLAUDE_AGENT_IMAGE)
	@echo "All images pushed."

## clean: Remove locally built images
clean:
	-$(CONTAINER_ENGINE) rmi $(DOCUMENT_SERVICE_IMAGE) 2>/dev/null
	-$(CONTAINER_ENGINE) rmi $(OPA_SERVICE_IMAGE) 2>/dev/null
	-$(CONTAINER_ENGINE) rmi $(CLAUDE_AGENT_IMAGE) 2>/dev/null
	@echo "Images removed."
