# Grafana Cloud Integration with HashiCorp Vault

This document explains how to integrate Grafana Cloud credentials stored in HashiCorp Vault with your Kubernetes cluster using ArgoCD, External Secrets Operator (ESO), and the Grafana k8s-monitoring Helm chart.

## Architecture Overview

```
┌─────────────────┐
│ HashiCorp Vault │
│  (External)     │
└────────┬────────┘
         │
         │ VAULT_ADDR/VAULT_TOKEN
         │
    ┌────▼──────────────────┐
    │  ArgoCD RepoServer    │
    │  (helmfile CMP)       │
    └────┬───────────────────┘
         │
         │ kubectl apply
         │
    ┌────▼────────────────────────────────┐
    │  External Secrets Operator (ESO)    │
    │  - Reads from Vault                 │
    │  - Creates Kubernetes Secrets       │
    └────┬─────────────────────────────────┘
         │
         │ Creates/Updates Secret
         │
    ┌────▼──────────────────────────────┐
    │  grafana-cloud-credentials Secret  │
    │  - username                        │
    │  - password                        │
    │  - url                             │
    └────┬───────────────────────────────┘
         │
         │ Referenced by
         │
    ┌────▼─────────────────────────────┐
    │  Grafana k8s-monitoring Chart     │
    │  - Alloy agents (DaemonSet)       │
    │  - kube-state-metrics             │
    │  - node-exporter                  │
    └──────────────────────────────────┘
```

## Prerequisites

1. **External Vault Instance**: Running Vault server with KV v2 secrets engine
2. **Vault Secrets Setup**: Credentials stored at:
   ```
   secret/gitops/dev/grafana-cloud
   {
     "username": "your-email@example.com",
     "password": "your-api-key",
     "url": "https://fleet-management-prod-018.grafana.net"
   }
   ```

3. **Kubernetes Environment Variables**: ArgoCD must have access to:
   - `VAULT_ADDR`: External Vault server URL
   - `VAULT_TOKEN`: Vault authentication token

## Implementation Steps

### 1. Environment Setup

Ensure your ArgoCD/helmfile environment has the required variables:

```bash
# In your CI/CD system or ArgoCD secret
export VAULT_ADDR="http://vault.example.com:8200"
export VAULT_TOKEN="hvs.your-token-here"
export CLUSTER_NAME="dev"
export CLUSTER_DOMAIN="example.com"
```

### 2. Helmfile Configuration

The helmfile automatically handles:

1. **Creating SecretStore** (monitoring namespace)
   - Points to external Vault server
   - Uses tokenSecretRef for authentication

2. **Creating ExternalSecret**
   - Pulls credentials from Vault path: `gitops/{environment}/grafana-cloud`
   - Creates a Kubernetes Secret named `grafana-cloud-credentials`
   - Auto-refreshes every hour

3. **Deploying k8s-monitoring Chart**
   - Automatically waits for ExternalSecret to be ready
   - References the Kubernetes Secret for credentials
   - Deploys Alloy agents, kube-state-metrics, node-exporter

### 3. Secret Path Convention

Organize Vault secrets by environment:

```
secret/gitops/dev/grafana-cloud
secret/gitops/staging/grafana-cloud
secret/gitops/prod/grafana-cloud
```

Each path contains:
- `username`: Grafana Cloud email or username
- `password`: Grafana Cloud API token
- `url`: Grafana Cloud instance URL

### 4. ArgoCD Application Configuration

Create an ArgoCD Application that uses helmfile:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-services
  namespace: argo-cd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-cluster-services
    targetRevision: main
    path: .
    plugin:
      name: helmfile
      env:
        - name: ENVIRONMENT
          value: dev
        - name: CLUSTER_NAME
          value: dev-cluster
        - name: CLUSTER_DOMAIN
          value: example.com
        - name: VAULT_ADDR
          valueFrom:
            secretKeyRef:
              name: vault-config
              key: addr
        - name: VAULT_TOKEN
          valueFrom:
            secretKeyRef:
              name: vault-config
              key: token
  destination:
    server: https://kubernetes.default.svc
    namespace: default
```

### 5. Creating ArgoCD Bootstrap Secret

Create the secret for Vault configuration before deploying:

```bash
kubectl create secret generic vault-config \
  -n argo-cd \
  --from-literal=addr="http://vault.vault.svc.cluster.local:8200" \
  --from-literal=token="hvs.your-token" \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Helm Chart Integration

The updated observability helmfile uses the `grafana/k8s-monitoring` chart which provides:

### Alloy Collectors
- **Kubernetes discovery**: Automatically discovers pods and nodes
- **Metrics collection**: Prometheus scraping from discovered targets
- **Log collection**: Loki log shipping from pod stdout/stderr
- **Trace collection**: OTLP receiver for distributed tracing

### Included Components
- **node-exporter**: Host-level metrics (CPU, memory, disk, network)
- **kube-state-metrics**: Kubernetes resource metrics
- **opencost**: (optional) Resource cost tracking

## Troubleshooting

### Secret Not Created
```bash
# Check ExternalSecret status
kubectl describe externalsecret -n monitoring grafana-cloud-credentials

# Check if SecretStore is ready
kubectl describe secretstore -n monitoring vault

# Verify Vault token is valid
kubectl get secret -n external-secrets external-secrets-vault-token
```

### Credentials Not Syncing
```bash
# Check ESO operator logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets -f

# Check if path exists in Vault
docker exec vault-container vault kv get secret/gitops/dev/grafana-cloud
```

### ArgoCD Sync Issues
```bash
# Verify helmfile rendering
helmfile -f helmfile.yaml -e dev template

# Check ArgoCD repo server logs
kubectl logs -n argo-cd deployment/argocd-repo-server -f
```

## Security Considerations

1. **Token Rotation**: Implement regular Vault token rotation
2. **RBAC**: Restrict SecretStore access to specific namespaces
3. **Audit Logging**: Enable Vault audit logs for compliance
4. **Secret Refresh**: ESO refreshes secrets hourly by default
5. **Network Policies**: Restrict traffic to Vault server

## Migration from Environment Variables

### Before (Environment Variables)
```bash
helm upgrade --install grafana-cloud \
  --set grafanaCloud.username="$GRAFANA_CLOUD_USERNAME" \
  --set grafanaCloud.password="$GRAFANA_CLOUD_PASSWORD"
```

### After (Vault Integration)
```bash
# No environment variables needed!
# ArgoCD/helmfile handles credential management automatically
# Credentials are synced from Vault every hour
```

## References

- [External Secrets Operator Documentation](https://external-secrets.io/)
- [Grafana k8s-monitoring Helm Chart](https://github.com/grafana/helm-charts/tree/main/charts/k8s-monitoring)
- [HashiCorp Vault Documentation](https://www.vaultproject.io/docs)
- [ArgoCD Helmfile Plugin](https://github.com/travisghansen/argo-cd-helmfile)
