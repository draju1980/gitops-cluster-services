# Cluster Services Bootstrap Guide

This directory contains all necessary files to bootstrap a Kubernetes cluster with ArgoCD and cluster services using GitOps principles with Vault secret management.

## Directory Structure

```
bootstrap/
├── README.md                        # This file
├── setup-vault-integration.sh       # Script to setup Vault credentials in Kubernetes
├── argocd/
│   ├── helm-values.yaml             # ArgoCD Helm chart values (helmfile plugin + Vault env vars)
│   ├── cluster-services-app.yaml    # ArgoCD Application manifest for cluster services
│   └── argocd-install.sh            # (Optional) Script to bootstrap ArgoCD itself
└── k3d/
    └── k3d-cluster.yaml             # (Optional) k3d cluster definition
```

## Prerequisites

Before starting, ensure you have:

1. **Kubernetes Cluster**: k3d, kind, minikube, or production cluster
   ```bash
   k3d cluster create mycluster
   ```

2. **Helm 3.x**: For chart management
   ```bash
   brew install helm
   helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
   helm repo add argoproj https://argoproj.github.io/argo-helm
   # (Add other repos as needed)
   ```

3. **kubectl**: For Kubernetes cluster access
   ```bash
   kubectl cluster-info
   ```

4. **External Vault Instance**: Running and accessible
   ```bash
   export VAULT_ADDR="http://vault.example.com:8200"
   export VAULT_TOKEN="hvs.your-token"
   
   # Verify access
   vault status
   ```

5. **Grafana Cloud Credentials**: Stored in Vault at the correct path
   ```bash
   vault kv put secret/gitops/dev/grafana-cloud \
     username='your-email@example.com' \
     password='your-api-key' \
     url='https://your-instance.grafana.net'
   ```

## Bootstrap Process

### Step 1: Create Kubernetes Cluster (if needed)

```bash
# Using k3d
k3d cluster create dev-cluster \
  -p "8080:80@loadbalancer" \
  -p "8443:443@loadbalancer" \
  --k3s-arg "--disable=metrics-server@server:*"

# Verify cluster is ready
kubectl get nodes
```

### Step 2: Setup Vault Integration

```bash
# Make script executable
chmod +x bootstrap/setup-vault-integration.sh

# Run setup script (requires VAULT_ADDR and VAULT_TOKEN env vars)
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="hvs.your-token"

./bootstrap/setup-vault-integration.sh argo-cd
```

This creates:
- `argo-cd` namespace
- `argocd-vault-config` secret with Vault credentials

### Step 3: Create Bootstrap Secrets

Create the bootstrap secrets required by ArgoCD:

```bash
kubectl create namespace argo-cd

# Create bootstrap secrets
kubectl create secret generic argocd-bootstrap-secrets \
  -n argo-cd \
  --from-literal=github-token="ghp_your-github-token" \
  --from-literal=cloudflare-token="your-cloudflare-api-token" \
  --from-literal=cloudflare-account-id="your-account-id" \
  --from-literal=argocd-admin-password-hash="$(htpasswd -b admin changeme | cut -d: -f2)" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Step 4: Install ArgoCD

```bash
# Add Argo Helm repository
helm repo add argoproj https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD with custom values
helm install argocd argoproj/argo-cd \
  -n argo-cd \
  -f bootstrap/argocd/helm-values.yaml

# Wait for ArgoCD to be ready
kubectl rollout status deployment/argocd-server -n argo-cd
```

### Step 5: Create Cluster Services Application

```bash
# Update the cluster-services-app.yaml with your values
# - Change repository URL to your fork
# - Update cluster name and domain
# - Ensure Vault credentials are correct

kubectl apply -f bootstrap/argocd/cluster-services-app.yaml

# Monitor sync status
kubectl get application -n argo-cd
kubectl describe application cluster-services -n argo-cd
```

### Step 6: Verify Deployment

```bash
# Check if secrets are synced from Vault
kubectl get externalsecrets -n monitoring
kubectl describe externalsecret grafana-cloud-credentials -n monitoring

# Check if secret was created
kubectl get secret -n monitoring grafana-cloud-credentials

# Check if Grafana monitoring is deployed
kubectl get pods -n monitoring
```

## Configuration

### Environment Variables

The helmfile uses these environment variables (passed through ArgoCD Application):

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CLUSTER_NAME` | Yes | - | Unique cluster identifier |
| `CLUSTER_DOMAIN` | Yes | - | Base domain for cluster services |
| `ENVIRONMENT` | No | `dev` | Environment name (dev, staging, prod) |
| `GITHUB_TOKEN` | No | - | GitHub personal access token |
| `VAULT_ADDR` | Yes | - | External Vault server URL |
| `VAULT_TOKEN` | Yes | - | Vault authentication token |
| `CLOUDFLARE_TOKEN` | No | - | Cloudflare API token |
| `CLOUDFLARE_ACCOUNT_ID` | No | - | Cloudflare account ID |

### Vault Secret Paths

Organize secrets by environment:

```
secret/gitops/dev/grafana-cloud
secret/gitops/staging/grafana-cloud
secret/gitops/prod/grafana-cloud
```

Each path must contain:
- `username`: Grafana Cloud email
- `password`: Grafana Cloud API token
- `url`: Grafana Cloud instance URL

## Troubleshooting

### ArgoCD Can't Access Vault

```bash
# Check if secret exists
kubectl get secret argocd-vault-config -n argo-cd

# Check helmfile plugin logs
kubectl logs -n argo-cd deployment/argocd-repo-server -c helmfile-cmp -f

# Verify Vault is accessible
kubectl run -it --rm vault-test --image=vault:latest -- \
  sh -c 'export VAULT_ADDR=http://vault.example.com:8200 && vault status'
```

### ExternalSecret Not Syncing

```bash
# Check ESO operator logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets -f

# Check SecretStore status
kubectl describe secretstore vault -n monitoring

# Verify Vault token is valid
kubectl get secret -n external-secrets external-secrets-vault-token -o jsonpath='{.data.token}' | base64 -d
```

### Helmfile Template Errors

```bash
# Render helmfile locally (requires VAULT_ADDR and VAULT_TOKEN)
helmfile -f ../helmfile.yaml -e dev template

# Check specific release
helmfile -f ../helmfile.yaml -e dev template --selector name=grafana-cloud-k8s-monitoring
```

## Upgrading

### Updating Helm Charts

```bash
# Update Helm repositories
helm repo update

# Check for available updates
helmfile -f ../helmfile.yaml status

# Upgrade specific release
helmfile -f ../helmfile.yaml -e dev upgrade --selector name=grafana-cloud-k8s-monitoring
```

### Rotating Vault Tokens

```bash
# Generate new token in Vault
vault token create

# Update the secret
kubectl patch secret argocd-vault-config -n argo-cd \
  -p '{"stringData":{"vault-token":"hvs.new-token"}}'

# Restart ArgoCD repo server to pick up new token
kubectl rollout restart deployment/argocd-repo-server -n argo-cd
```

## Security Considerations

1. **Secret Management**: Store bootstrap secrets in Sealed Secrets or External Secrets
2. **RBAC**: Restrict ArgoCD permissions per project
3. **Network Policy**: Limit traffic to Vault server
4. **Audit Logging**: Enable Kubernetes and Vault audit logs
5. **Token Rotation**: Implement regular Vault token rotation
6. **Git Repository**: Keep the git repository private (Vault secrets not in git)

## References

- [Grafana Cloud Kubernetes Monitoring](../docs/GRAFANA_CLOUD_VAULT_INTEGRATION.md)
- [External Secrets Operator](https://external-secrets.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Helmfile Documentation](https://helmfile.readthedocs.io/)
- [HashiCorp Vault](https://www.vaultproject.io/)
