# Quick Start: Grafana Cloud Integration with Vault

This guide walks you through setting up Grafana Cloud monitoring for your Kubernetes cluster using HashiCorp Vault for secret management and ArgoCD for GitOps deployment.

## 5-Minute Setup (One-Time Bootstrap)

> **Note:** This bootstrap process is run ONCE to initialize ArgoCD with Vault integration.
> After bootstrap, ArgoCD stores Vault credentials internally - other team members don't need VAULT_ADDR/VAULT_TOKEN.

### 1. Store Credentials in Vault (Admin)

```bash
# Set your Vault connection (one-time)
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="hvs.your-token"

# Store Grafana Cloud credentials
vault kv put secret/gitops/dev/grafana-cloud \
  username="your-email@example.com" \
  password="your-grafana-cloud-api-token" \
  url="https://your-instance.grafana.net"

# Verify
vault kv get secret/gitops/dev/grafana-cloud
```

### 2. Create Kubernetes Cluster

```bash
# Using k3d
k3d cluster create dev-cluster

# Or using kind
kind create cluster --name dev-cluster
```

### 3. Run Bootstrap Script (Admin Only)

```bash
# Navigate to project
cd /Users/mdraju/labs/gitops-cluster-services

# Run setup script with Vault credentials
# ⚠️  Only the cluster admin needs to run this ONCE
export VAULT_ADDR="http://127.0.0.1:8200"
export VAULT_TOKEN="hvs.your-token"

./bootstrap/setup-vault-integration.sh argo-cd

# This creates the argocd-vault-config secret in Kubernetes
# After this, Vault credentials are stored securely in K8s
```

### 4. Install ArgoCD (Admin Only)

```bash
helm repo add argoproj https://argoproj.github.io/argo-helm
helm repo update

# This deployment reads Vault credentials from argocd-vault-config secret
helm install argocd argoproj/argo-cd \
  -n argo-cd \
  -f bootstrap/argocd/helm-values.yaml

kubectl rollout status deployment/argocd-server -n argo-cd
```

### ✅ Vault Integration Complete!
Once deployed, ArgoCD's helmfile plugin automatically:
- Reads VAULT_ADDR/VAULT_TOKEN from the `argocd-vault-config` secret
- Authenticates with Vault during helmfile rendering
- Pulls Grafana Cloud credentials on-demand
- Other team members can now deploy without Vault credentials!

### 5. Create Bootstrap Secrets

```bash
kubectl create secret generic argocd-bootstrap-secrets \
  -n argo-cd \
  --from-literal=github-token="ghp_xxx" \
  --from-literal=cloudflare-token="xxx" \
  --from-literal=cloudflare-account-id="xxx" \
  --from-literal=argocd-admin-password-hash="$(echo -n 'admin:password' | md5sum | cut -d' ' -f1)"
```

### 6. Deploy Cluster Services

```bash
# Update the app values
sed -i 's/draju1980/YOUR_USERNAME/g' bootstrap/argocd/cluster-services-app.yaml
sed -i 's/example.com/YOUR_DOMAIN.com/g' bootstrap/argocd/cluster-services-app.yaml

# Deploy
kubectl apply -f bootstrap/argocd/cluster-services-app.yaml

# Monitor
kubectl get application -n argo-cd
kubectl describe application cluster-services -n argo-cd
```

## Verification

### Check External Secret Sync

```bash
# Wait for secret to be created from Vault
kubectl wait --for=condition=ready=true \
  externalsecret/grafana-cloud-credentials \
  -n monitoring --timeout=120s

# Verify secret exists
kubectl get secret grafana-cloud-credentials -n monitoring

# View secret contents (base64 encoded)
kubectl get secret grafana-cloud-credentials -n monitoring -o json | jq '.data'
```

### Check Monitoring Components

```bash
# List all monitoring pods
kubectl get pods -n monitoring

# Check if Alloy agents are running
kubectl get daemonset -n monitoring
kubectl logs -n monitoring daemonset/grafana-cloud-k8s-monitoring-alloy -f

# Check if kube-state-metrics is running
kubectl get deployment -n monitoring

# Verify data flow to Grafana Cloud
kubectl logs -n monitoring -l app.kubernetes.io/name=alloy --tail=20
```

### Monitor ArgoCD Sync

```bash
# Get application status
kubectl get application cluster-services -n argo-cd -o json | jq '.status'

# Check specific resource sync
kubectl get externalsecret -n monitoring
kubectl get secretstore -n monitoring

# View ArgoCD repo server logs (helmfile plugin)
kubectl logs -n argo-cd deployment/argocd-repo-server -c helmfile-cmp -f
```

## Understanding the Architecture

```
Vault Server (External)
       ↓
   VAULT_ADDR/VAULT_TOKEN (env vars)
       ↓
   ArgoCD Repo Server (helmfile plugin)
       ↓
   Helmfile Template Rendering
       ↓
   External Secrets Operator
       ↓
   Kubernetes Secret (grafana-cloud-credentials)
       ↓
   k8s-monitoring Helm Chart
       ↓
   Alloy Agents (DaemonSet)
   kube-state-metrics (Deployment)
       ↓
   Grafana Cloud (Prometheus, Loki)
```

## Configuration

### Environment-Based Secrets

The helmfile automatically uses `${ENVIRONMENT}` to fetch secrets:

```yaml
# If ENVIRONMENT=dev, it fetches from:
secret/gitops/dev/grafana-cloud

# If ENVIRONMENT=staging, it fetches from:
secret/gitops/staging/grafana-cloud

# If ENVIRONMENT=prod, it fetches from:
secret/gitops/prod/grafana-cloud
```

Create all three paths in Vault for multi-environment support:

```bash
# Dev
vault kv put secret/gitops/dev/grafana-cloud \
  username="dev@company.com" \
  password="dev-api-token" \
  url="https://dev-instance.grafana.net"

# Staging
vault kv put secret/gitops/staging/grafana-cloud \
  username="staging@company.com" \
  password="staging-api-token" \
  url="https://staging-instance.grafana.net"

# Production
vault kv put secret/gitops/prod/grafana-cloud \
  username="prod@company.com" \
  password="prod-api-token" \
  url="https://prod-instance.grafana.net"
```

## What Gets Deployed

The helmfile deploys the following components:

### Monitoring Stack (k8s-monitoring)
- **Alloy**: Collects metrics, logs, and traces from Kubernetes
- **kube-state-metrics**: Kubernetes resource metrics
- **node-exporter**: Host-level system metrics
- **Service Discovery**: Automatically discovers services and pod targets

### Data Destinations
- **Prometheus**: Metrics pushed to Grafana Cloud
- **Loki**: Logs pushed to Grafana Cloud
- **Tempo** (optional): Traces pushed to Grafana Cloud

### Integration Points
- **Vault**: Stores Grafana Cloud credentials
- **External Secrets Operator (ESO)**: Syncs secrets from Vault
- **ArgoCD**: GitOps deployment and management

## Common Operations

### View Metrics in Grafana

1. Log into your Grafana Cloud instance
2. Navigate to Explore → Prometheus
3. Query: `up` to see all targets
4. Query: `kube_node_labels` to see nodes
5. Query: `rate(container_cpu_usage_seconds_total[5m])` for CPU usage

### View Logs in Grafana

1. Navigate to Explore → Loki
2. Select labels: `namespace="monitoring"`
3. See logs from monitoring components

### Update Credentials

```bash
# Update in Vault
vault kv put secret/gitops/dev/grafana-cloud \
  username="new-email@company.com" \
  password="new-api-token" \
  url="https://new-instance.grafana.net"

# ESO will automatically sync (1-hour refresh interval)
# Check sync status
kubectl describe externalsecret grafana-cloud-credentials -n monitoring
```

### Scale Monitoring Components

```bash
# Edit the helmfile to adjust replicas/resources
# releases/observability.yaml.gotmpl

# Then sync ArgoCD
kubectl patch application cluster-services -n argo-cd \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}' --type=merge
```

## Troubleshooting

### Secret Not Created

```bash
# Check ExternalSecret status
kubectl describe externalsecret grafana-cloud-credentials -n monitoring

# Check ESO operator logs
kubectl logs -n external-secrets -l app.kubernetes.io/name=external-secrets -f

# Verify Vault token in secret
kubectl get secret external-secrets-vault-token -n external-secrets -o jsonpath='{.data.token}' | base64 -d
```

### Alloy Not Collecting Metrics

```bash
# Check Alloy pod logs
kubectl logs -n monitoring daemonset/grafana-cloud-k8s-monitoring-alloy -f

# Check if remote write endpoint is reachable
kubectl run -it --rm debug --image=curlimages/curl -- \
  sh -c 'curl -v https://prometheus-blocks-prod-us-central1.grafana.net/api/prom/push'

# Verify credentials are correct
kubectl get secret grafana-cloud-credentials -n monitoring -o jsonpath='{.data.username}' | base64 -d
```

### ArgoCD Sync Errors

```bash
# Check ArgoCD application status
kubectl describe application cluster-services -n argo-cd

# Check repo server logs
kubectl logs -n argo-cd deployment/argocd-repo-server -f

# Check helmfile plugin logs
kubectl logs -n argo-cd deployment/argocd-repo-server -c helmfile-cmp -f

# Manually test helmfile rendering
kubectl exec -n argo-cd deployment/argocd-repo-server -c helmfile-cmp -- \
  helmfile -f /tmp/helmfile.yaml template
```

## Next Steps

1. **Monitor the deployment**: Check Grafana Cloud dashboards
2. **Setup dashboards**: Create custom Grafana dashboards for your services
3. **Configure alerts**: Set up alerting rules in Grafana Cloud
4. **Scale out**: Deploy to staging and production clusters
5. **Optimize costs**: Review Grafana Cloud usage and optimize metric retention

## References

- [Grafana Cloud Kubernetes Monitoring](docs/GRAFANA_CLOUD_VAULT_INTEGRATION.md)
- [Bootstrap Documentation](bootstrap/README.md)
- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/set-up/install/kubernetes/)
- [External Secrets Operator](https://external-secrets.io/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review logs: `kubectl logs -f -n monitoring`
3. Check Vault connectivity: `vault status`
4. Verify ArgoCD sync: `kubectl describe application cluster-services -n argo-cd`
