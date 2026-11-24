# Vault Integration Update Summary

## What Changed

This update integrates HashiCorp Vault for secure credential management with Grafana Cloud, replacing environment variable-based secret passing with External Secrets Operator (ESO) pull-based secret synchronization.

## Files Modified

### 1. `releases/observability.yaml.gotmpl`
**What**: Updated Grafana monitoring configuration
**Changes**:
- Removed direct `grafana-agent` and `grafana-agent-node` releases
- Added `monitoring-secretstore` release to create SecretStore and ExternalSecret resources
- Added `grafana-cloud-k8s-monitoring` release using Grafana's official k8s-monitoring chart
- Added optional `kube-prometheus-stack` release (disabled by default)
- Secrets are now pulled from Vault instead of passed as environment variables

**Benefits**:
- ✅ Credentials never stored in Git or environment variables
- ✅ Automatic secret rotation (1-hour refresh interval)
- ✅ Centralized credential management via Vault
- ✅ Uses modern Alloy agent (better than legacy Grafana Agent)
- ✅ Comprehensive Kubernetes monitoring with pre-configured collectors

### 2. `bootstrap/argocd/helm-values.yaml`
**What**: Updated ArgoCD Helm values for Vault integration
**Changes**:
- Added `VAULT_ADDR` and `VAULT_TOKEN` environment variables to helmfile CMP plugin
- These allow ArgoCD's helmfile plugin to authenticate with external Vault

**Benefits**:
- ✅ ArgoCD can now read secrets from Vault during helmfile rendering
- ✅ Enables GitOps workflows with external secret management
- ✅ No hardcoded secrets in Git repository

## New Files Created

### 1. `docs/GRAFANA_CLOUD_VAULT_INTEGRATION.md`
Comprehensive documentation covering:
- Architecture overview with diagrams
- Prerequisites and setup steps
- Helm chart integration details
- Troubleshooting guide
- Security considerations
- Migration guide from environment variables

### 2. `bootstrap/setup-vault-integration.sh`
Automated setup script that:
- Creates `argo-cd` namespace
- Creates `argocd-vault-config` secret with Vault credentials
- Provides next steps instructions
- Makes bootstrapping easier and reproducible

### 3. `bootstrap/argocd/cluster-services-app.yaml`
Complete ArgoCD Application manifest including:
- Application configuration with helmfile plugin setup
- All required environment variables
- AppProject definition with RBAC
- Bootstrap secrets configuration
- Example Vault configuration secret

### 4. `bootstrap/README.md`
Step-by-step bootstrap guide covering:
- Prerequisites verification
- Cluster creation
- Vault setup
- ArgoCD installation
- Application deployment
- Verification steps
- Troubleshooting
- Security considerations

### 5. `QUICKSTART.md`
Quick reference guide with:
- 5-minute setup process
- Configuration examples for multiple environments
- Verification commands
- Architecture explanation
- Common operations
- Troubleshooting tips

## Architecture Changes

### Before (Environment Variables)
```
Environment Variables (GRAFANA_CLOUD_USERNAME, etc)
         ↓
    Helmfile Values
         ↓
    Helm Chart
         ↓
    Pod Environment Variables
```

### After (Vault Integration)
```
Vault Server (External)
         ↓
    External Secrets Operator
         ↓
    Kubernetes Secret
         ↓
    Helm Chart (via secretRef)
         ↓
    Pod Volume Mounts
```

## Secret Path Structure

Organize secrets by environment:

```
secret/gitops/dev/grafana-cloud
├── username: "user@company.com"
├── password: "api-token"
└── url: "https://instance.grafana.net"

secret/gitops/staging/grafana-cloud
├── username: "staging@company.com"
├── password: "staging-token"
└── url: "https://staging-instance.grafana.net"

secret/gitops/prod/grafana-cloud
├── username: "prod@company.com"
├── password: "prod-token"
└── url: "https://prod-instance.grafana.net"
```

## Deployment Requirements

### Environment Variables (from ArgoCD)
```
VAULT_ADDR=http://vault.example.com:8200
VAULT_TOKEN=hvs.your-token
CLUSTER_NAME=dev-cluster
CLUSTER_DOMAIN=example.com
ENVIRONMENT=dev
```

### Bootstrap Secrets (Kubernetes)
```
argocd-bootstrap-secrets:
  - github-token
  - cloudflare-token
  - cloudflare-account-id
  - argocd-admin-password-hash

argocd-vault-config:
  - vault-addr
  - vault-token
```

## Migration Steps

If you're currently using environment variables:

### 1. Create Vault Secrets
```bash
vault kv put secret/gitops/dev/grafana-cloud \
  username="$GRAFANA_CLOUD_USERNAME" \
  password="$GRAFANA_CLOUD_PROM_PASSWORD" \
  url="$GRAFANA_CLOUD_PROM_URL"
```

### 2. Update ArgoCD
Deploy the updated `helm-values.yaml` for ArgoCD:
```bash
helm upgrade argocd argoproj/argo-cd \
  -n argo-cd \
  -f bootstrap/argocd/helm-values.yaml
```

### 3. Create Vault Config Secret
```bash
./bootstrap/setup-vault-integration.sh argo-cd
```

### 4. Update ArgoCD Application
Apply the new `cluster-services-app.yaml`:
```bash
kubectl apply -f bootstrap/argocd/cluster-services-app.yaml
```

### 5. Remove Old Environment Variables
Stop passing `GRAFANA_CLOUD_*` environment variables to helmfile.

## Key Improvements

| Aspect | Before | After |
|--------|--------|-------|
| **Secret Storage** | Environment Variables | Vault |
| **Secret Rotation** | Manual | Automatic (1 hour) |
| **Credential Exposure** | High (env vars visible) | Low (only in Vault) |
| **Multi-Environment** | Difficult (many env vars) | Easy (one path per env) |
| **Git Compliance** | No secrets in Git | No secrets in Git |
| **Monitoring Chart** | grafana-agent | k8s-monitoring (Alloy-based) |
| **Configuration** | Manual helm install | GitOps via ArgoCD |

## Validation Checklist

After deployment, verify:

- [ ] ExternalSecret is synced: `kubectl get externalsecret -n monitoring`
- [ ] Secret is created: `kubectl get secret grafana-cloud-credentials -n monitoring`
- [ ] Alloy pods are running: `kubectl get pods -n monitoring`
- [ ] Logs flowing to Grafana Cloud: Check Grafana Cloud Loki dashboard
- [ ] Metrics flowing to Grafana Cloud: Check Grafana Cloud Prometheus dashboard
- [ ] ArgoCD application is synced: `kubectl get application -n argo-cd`

## Rollback Plan

If you need to revert:

1. Keep the old `releases/observability.yaml.gotmpl.backup`
2. Revert to previous version: `git checkout releases/observability.yaml.gotmpl`
3. Update ArgoCD: `helm upgrade argocd ... -f old-helm-values.yaml`
4. Sync ArgoCD: `kubectl patch application ... --type=merge`

## Security Notes

1. **Secret Token**: The Vault token in `argocd-vault-config` has access to secrets
   - Rotate regularly: `vault token renew`
   - Consider Kubernetes auth instead of tokens
   
2. **RBAC**: ESO service account should have minimal permissions
   - Already configured in `vault/secretstore.yaml`
   
3. **Network**: Ensure ArgoCD can reach Vault server
   - Check firewalls and network policies
   
4. **Audit**: Enable Vault audit logs for compliance
   - Verify all secret access is logged

## Support & Documentation

- **Quick Start**: See `QUICKSTART.md`
- **Detailed Guide**: See `bootstrap/README.md`
- **Architecture**: See `docs/GRAFANA_CLOUD_VAULT_INTEGRATION.md`
- **Bootstrap Script**: See `bootstrap/setup-vault-integration.sh`

## Questions?

Refer to:
1. `QUICKSTART.md` for quick answers
2. `bootstrap/README.md` for setup issues
3. `docs/GRAFANA_CLOUD_VAULT_INTEGRATION.md` for architecture details
4. Troubleshooting sections in any of the above
