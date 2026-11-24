#!/bin/bash
# Setup script for Vault integration with ArgoCD and Helmfile
# This script creates the necessary Kubernetes secrets for Vault access

set -e

NAMESPACE="${1:-argo-cd}"
VAULT_ADDR="${VAULT_ADDR:-}"
VAULT_TOKEN="${VAULT_TOKEN:-}"

if [ -z "$VAULT_ADDR" ] || [ -z "$VAULT_TOKEN" ]; then
    echo "Error: VAULT_ADDR and VAULT_TOKEN environment variables must be set"
    echo "Usage: VAULT_ADDR=http://vault.example.com:8200 VAULT_TOKEN=hvs.xxx $0 [namespace]"
    exit 1
fi

echo "Setting up Vault integration in namespace: $NAMESPACE"

# Create namespace if it doesn't exist
kubectl get namespace "$NAMESPACE" &>/dev/null || kubectl create namespace "$NAMESPACE"

# Create secret for ArgoCD/helmfile to access Vault
echo "Creating argocd-vault-config secret..."
kubectl create secret generic argocd-vault-config \
    -n "$NAMESPACE" \
    --from-literal=vault-addr="$VAULT_ADDR" \
    --from-literal=vault-token="$VAULT_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -

echo "✓ Vault integration setup complete!"
echo ""
echo "Next steps:"
echo "1. Deploy ArgoCD with the updated helm-values.yaml"
echo "2. Create Grafana Cloud secret in Vault:"
echo ""
echo "   docker exec vault-container vault kv put secret/gitops/dev/grafana-cloud \\"
echo "     username='your-email@example.com' \\"
echo "     password='your-api-key' \\"
echo "     url='https://your-instance.grafana.net'"
echo ""
echo "3. Create an ArgoCD Application pointing to your helmfile"
echo ""
echo "4. Monitor the deployment:"
echo "   kubectl logs -f -n argo-cd deployment/argocd-repo-server"
