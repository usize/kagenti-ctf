#!/usr/bin/env bash
# Teardown the leaked-access-token CTF demo
#
# Removes all Kubernetes resources created by setup.sh.
# Does NOT delete the Kind cluster or Kagenti installation.
#
# Usage: ./scripts/teardown.sh
set -euo pipefail

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${DEMO_DIR}"

echo "============================================"
echo "  Leaked Access Token CTF Demo — Teardown"
echo "============================================"
echo ""

echo "==> Removing Claude agent..."
kubectl delete -f manifests/claude-agent.yaml --ignore-not-found 2>/dev/null || true

echo "==> Removing AuthBridge configuration..."
kubectl delete -f manifests/authbridge-config.yaml --ignore-not-found 2>/dev/null || true

echo "==> Removing Claude credentials secret..."
kubectl delete secret claude-credentials -n ctf-claude --ignore-not-found 2>/dev/null || true

echo "==> Removing document-service and OPA..."
kubectl delete -f manifests/document-service.yaml --ignore-not-found 2>/dev/null || true

echo "==> Removing RBAC..."
kubectl delete -f manifests/rbac.yaml --ignore-not-found 2>/dev/null || true

echo "==> Removing network policy (if applied)..."
kubectl delete -f manifests/networkpolicy.yaml --ignore-not-found 2>/dev/null || true

echo "==> Removing namespaces..."
kubectl delete -f manifests/namespace.yaml --ignore-not-found 2>/dev/null || true

echo ""
echo "==> Teardown complete."
echo "    The Kind cluster and Kagenti installation are untouched."
