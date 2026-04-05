#!/usr/bin/env bash
# Main setup script for the leaked-access-token CTF demo
#
# Orchestrates: prereq check → build → deploy → configure Keycloak
#
# Usage: ./scripts/setup.sh
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${DEMO_DIR}"

echo "============================================"
echo "  Leaked Access Token CTF Demo — Setup"
echo "============================================"
echo ""

# -------------------------------------------------------------------
# Step 1: Prerequisite checks
# -------------------------------------------------------------------
echo "==> Checking prerequisites..."

for cmd in docker kind kubectl curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '${cmd}' is required but not found."
        exit 1
    fi
done

# Check Kind cluster exists
if ! kind get clusters 2>/dev/null | grep -q "^kagenti$"; then
    echo "ERROR: Kind cluster 'kagenti' not found."
    echo "       Install Kagenti first:"
    echo "         cd /path/to/kagenti && ./deployments/ansible/run-install.sh --env dev"
    exit 1
fi

# Check kubectl context
CONTEXT=$(kubectl config current-context 2>/dev/null || true)
if [[ "${CONTEXT}" != *"kagenti"* ]]; then
    echo "WARNING: Current kubectl context is '${CONTEXT}', expected 'kind-kagenti'."
    echo "         Switching context..."
    kubectl config use-context kind-kagenti
fi

echo "    All prerequisites satisfied."
echo ""

# -------------------------------------------------------------------
# Step 2: Handle API credentials
# -------------------------------------------------------------------
echo "==> Checking API credentials..."

# Check for Vertex AI config first (preferred), then Anthropic API key
if [ -f "credentials/vertex-project-id" ]; then
    echo "    Found Vertex AI credentials"
elif [ -f "credentials/api-key" ]; then
    echo "    Found Anthropic API key"
elif [ -n "${ANTHROPIC_VERTEX_PROJECT_ID:-}" ] && [ "${CLAUDE_CODE_USE_VERTEX:-}" = "1" ]; then
    echo "    Detected Vertex AI environment variables"
    echo "    Writing Vertex config to credentials/..."
    echo "1" > credentials/use-vertex
    echo "${ANTHROPIC_VERTEX_PROJECT_ID}" > credentials/vertex-project-id
    # Copy ADC credentials if available
    ADC_PATH="${HOME}/.config/gcloud/application_default_credentials.json"
    if [ -f "${ADC_PATH}" ]; then
        cp "${ADC_PATH}" credentials/adc.json
        echo "    Copied ADC credentials"
    else
        echo "    WARNING: No ADC credentials found at ${ADC_PATH}"
        echo "    Run: gcloud auth application-default login"
    fi
elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    echo "    Detected ANTHROPIC_API_KEY environment variable"
    echo "${ANTHROPIC_API_KEY}" > credentials/api-key
else
    echo ""
    echo "    ================================================================"
    echo "    WARNING: API credentials are required to run Claude."
    echo "    These will be stored as a Kubernetes secret and NEVER committed."
    echo "    ================================================================"
    echo ""
    echo "    Options:"
    echo "      1. Set CLAUDE_CODE_USE_VERTEX=1 and ANTHROPIC_VERTEX_PROJECT_ID"
    echo "      2. Set ANTHROPIC_API_KEY"
    echo "      3. Create credentials/api-key or credentials/vertex-project-id"
    echo ""
    read -rp "    Enter your ANTHROPIC_API_KEY (or press Enter to skip): " API_KEY
    if [ -n "${API_KEY}" ]; then
        echo "${API_KEY}" > credentials/api-key
        echo "    Saved to credentials/api-key"
    else
        echo "    Skipped — Claude won't be able to call the API."
    fi
fi

echo ""

# -------------------------------------------------------------------
# Step 3: Build images
# -------------------------------------------------------------------
echo "==> Building container images..."
make build

echo ""

# -------------------------------------------------------------------
# Step 4: Load images into Kind
# -------------------------------------------------------------------
echo "==> Loading images into Kind cluster..."
make load

echo ""

# -------------------------------------------------------------------
# Step 5: CoreDNS rewrite for keycloak.localtest.me
# -------------------------------------------------------------------
# .localtest.me resolves to 127.0.0.1 via public DNS, which is wrong
# inside a pod. Add a CoreDNS rewrite so keycloak.localtest.me resolves
# to the Keycloak service cluster-wide.
echo "==> Configuring CoreDNS rewrite for keycloak.localtest.me..."

COREFILE=$(kubectl get cm coredns -n kube-system -o jsonpath='{.data.Corefile}')
if echo "${COREFILE}" | grep -q "rewrite name keycloak.localtest.me"; then
    echo "    CoreDNS rewrite already configured."
else
    # Insert the rewrite rule after the "ready" directive
    PATCHED=$(echo "${COREFILE}" | sed '/^[[:space:]]*ready$/a\
    rewrite name keycloak.localtest.me keycloak-service.keycloak.svc.cluster.local
')
    kubectl get cm coredns -n kube-system -o json | \
        jq --arg corefile "${PATCHED}" '.data.Corefile = $corefile' | \
        kubectl apply -f -
    # Restart CoreDNS to pick up the change
    kubectl rollout restart deployment/coredns -n kube-system
    kubectl rollout status deployment/coredns -n kube-system --timeout=60s
    echo "    CoreDNS rewrite configured and reloaded."
fi

echo ""

# -------------------------------------------------------------------
# Step 6: Deploy namespaces and RBAC
# -------------------------------------------------------------------
echo "==> Deploying namespaces and RBAC..."
kubectl apply -f manifests/namespace.yaml
kubectl apply -f manifests/rbac.yaml

echo ""

# -------------------------------------------------------------------
# Step 7: Deploy document-service and OPA
# -------------------------------------------------------------------
echo "==> Deploying document-service and OPA..."
kubectl apply -f manifests/document-service.yaml

echo "    Waiting for OPA service..."
kubectl rollout status deployment/opa-service -n ctf-demo --timeout=120s

echo "    Waiting for document-service..."
kubectl rollout status deployment/document-service -n ctf-demo --timeout=120s

echo ""

# -------------------------------------------------------------------
# Step 7: Configure Keycloak
# -------------------------------------------------------------------
echo "==> Configuring Keycloak..."

# Port-forward Keycloak if needed
KEYCLOAK_PID=""
if ! curl -s -o /dev/null -w "%{http_code}" http://keycloak.localtest.me:8080/realms/master 2>/dev/null | grep -q "200"; then
    echo "    Setting up port-forward to Keycloak..."
    KC_SVC=$(kubectl get svc -A -l app=keycloak -o jsonpath='{.items[0].metadata.namespace}/{.items[0].metadata.name}' 2>/dev/null || \
             kubectl get svc -A -l app.kubernetes.io/name=keycloak -o jsonpath='{.items[0].metadata.namespace}/{.items[0].metadata.name}' 2>/dev/null || \
             echo "keycloak/keycloak-service")
    KC_NS="${KC_SVC%%/*}"
    KC_NAME="${KC_SVC##*/}"
    kubectl port-forward -n "${KC_NS}" "svc/${KC_NAME}" 8080:8080 &>/dev/null &
    KEYCLOAK_PID=$!
    sleep 3
fi

bash keycloak/configure.sh

echo ""

# -------------------------------------------------------------------
# Step 9: Deploy AuthBridge config
# -------------------------------------------------------------------
echo "==> Deploying AuthBridge configuration..."
kubectl apply -f manifests/authbridge-config.yaml

echo ""

# -------------------------------------------------------------------
# Step 10: Create Claude credentials secrets
# -------------------------------------------------------------------
echo "==> Creating Claude credentials..."

# Build secret args based on which credentials are available
SECRET_ARGS=""
if [ -f "credentials/vertex-project-id" ]; then
    SECRET_ARGS="--from-file=vertex-project-id=credentials/vertex-project-id"
    SECRET_ARGS="${SECRET_ARGS} --from-file=use-vertex=credentials/use-vertex"
    echo "    Using Vertex AI credentials"
fi
if [ -f "credentials/api-key" ]; then
    SECRET_ARGS="${SECRET_ARGS} --from-file=api-key=credentials/api-key"
    echo "    Using Anthropic API key"
fi

if [ -n "${SECRET_ARGS}" ]; then
    kubectl create secret generic claude-credentials \
        -n ctf-claude ${SECRET_ARGS} \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "    Secret 'claude-credentials' created."
else
    echo "    No credentials found. Claude won't be able to call the API."
fi

# ADC credentials for Vertex AI (separate secret)
if [ -f "credentials/adc.json" ]; then
    kubectl create secret generic gcloud-adc \
        -n ctf-claude \
        --from-file=application_default_credentials.json=credentials/adc.json \
        --dry-run=client -o yaml | kubectl apply -f -
    echo "    Secret 'gcloud-adc' created."
fi

echo ""

# -------------------------------------------------------------------
# Step 11: Deploy Claude agent pod
# -------------------------------------------------------------------
echo "==> Deploying Claude agent pod..."
kubectl apply -f manifests/claude-agent.yaml

echo "    Waiting for Claude agent pod..."
kubectl rollout status deployment/claude-agent -n ctf-claude --timeout=180s

echo ""

# -------------------------------------------------------------------
# Step 12: Post-deploy Keycloak scope assignment
# -------------------------------------------------------------------
# The Claude agent pod's client-registration sidecar auto-registers a
# Keycloak client and creates an audience scope. We need to assign that
# scope to ctf-demo-cli so Alex's tokens include Claude's audience
# (required for RFC 8693 token exchange).
echo "==> Running post-deploy Keycloak configuration..."
sleep 5  # Wait for client-registration to complete
bash keycloak/configure.sh

if [ -n "${KEYCLOAK_PID}" ]; then
    kill "${KEYCLOAK_PID}" 2>/dev/null || true
fi

echo ""

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------
echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""
echo "  Next steps:"
echo "    1. Run the demo:  ./scripts/run-demo.sh"
echo "    2. Or manually:"
echo "       ./scripts/generate-token.sh     # Get Alex's token"
echo "       ./scripts/run-demo.sh           # Launch Claude with leaked token"
echo ""
echo "  Teardown:"
echo "    ./scripts/teardown.sh"
echo ""
