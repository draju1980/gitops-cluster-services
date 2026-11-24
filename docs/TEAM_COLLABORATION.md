# Team Collaboration with Vault Integration

This document explains how teams can collaborate on this GitOps setup without exposing Vault credentials to every team member.

## The Bootstrap Admin vs Team Member Workflow

```
                        ┌─────────────────────────────────────┐
                        │  BOOTSTRAP PHASE (Admin Only)       │
                        │  One-time setup                      │
                        └────────────┬────────────────────────┘
                                     │
                    ┌────────────────┴────────────────┐
                    │                                 │
        1. Set VAULT_ADDR env var        2. Set VAULT_TOKEN env var
        3. Run bootstrap script           4. Install ArgoCD
        5. Create K8s secrets
                    │
                    ▼
        ┌──────────────────────────┐
        │ argocd-vault-config      │  ◄── Stored securely in Kubernetes
        │ ├─ vault-addr            │
        │ └─ vault-token           │
        └──────────────────────────┘
                    │
         ┌──────────┴───────────┐
         │                      │
         ▼                      ▼
    ┌─────────────┐        ┌──────────────┐
    │ ADMIN USERS │        │ TEAM MEMBERS │
    │  Can:       │        │  Can:        │
    │ • Deploy    │        │ • Deploy     │
    │ • Manage    │        │ • Manage     │
    │            │        │  (via ArgoCD)│
    │ Needs:     │        │              │
    │ • kubectl   │        │ Needs:       │
    │ • Git       │        │ • kubectl    │
    │            │        │ • Git        │
    │ NO VAULT    │        │              │
    │ CREDS!     │        │ NO VAULT     │
    │            │        │ CREDS!      │
    └─────────────┘        └──────────────┘
```

## Role Definitions

### Bootstrap Administrator (One Person)

**Responsibilities:**
- Run the bootstrap setup script once
- Create Vault credentials in Kubernetes
- Deploy ArgoCD with Vault integration
- Manage Vault token rotation (periodic)
- Troubleshoot ArgoCD/Vault issues

**Needs:**
```bash
✓ Access to Vault (VAULT_ADDR, VAULT_TOKEN)
✓ kubectl access to Kubernetes cluster
✓ Git repository access
✓ Helm installed
```

**Runs (One-Time):**
```bash
export VAULT_ADDR="http://vault.example.com:8200"
export VAULT_TOKEN="hvs.admin-token"

./bootstrap/setup-vault-integration.sh argo-cd
helm install argocd argoproj/argo-cd -n argo-cd -f bootstrap/argocd/helm-values.yaml
kubectl apply -f bootstrap/argocd/cluster-services-app.yaml
```

### Team Members (Everyone Else)

**Responsibilities:**
- Update Git repository (helmfile, values, etc.)
- Monitor ArgoCD application sync status
- Review Grafana Cloud dashboards
- Troubleshoot application issues

**Needs:**
```bash
✓ kubectl access to Kubernetes cluster
✓ Git repository access
✓ Grafana Cloud access (view dashboards)
✗ NO Vault credentials needed!
✗ NO VAULT_ADDR env var needed!
✗ NO VAULT_TOKEN env var needed!
```

**Standard Workflow:**
```bash
# Clone repository
git clone https://github.com/your-org/gitops-cluster-services.git
cd gitops-cluster-services

# Make changes
vi releases/observability.yaml.gotmpl
vi helmfile.yaml

# Commit and push
git add .
git commit -m "Update monitoring configuration"
git push origin main

# ArgoCD automatically syncs changes
# No Vault credentials required!
```

## Multi-Environment Example

### Environment Setup

```
Dev Cluster (developer1)
  └─ Vault: http://vault.example.com:8200
  └─ VAULT_TOKEN: hvs.dev-token (bootstrap only)
  └─ CLUSTER_NAME: dev-cluster
  └─ ENVIRONMENT: dev
  └─ Credentials: secret/gitops/dev/grafana-cloud

Staging Cluster (developer2)
  └─ Vault: http://vault.example.com:8200
  └─ VAULT_TOKEN: hvs.staging-token (bootstrap only)
  └─ CLUSTER_NAME: staging-cluster
  └─ ENVIRONMENT: staging
  └─ Credentials: secret/gitops/staging/grafana-cloud

Prod Cluster (sre-team)
  └─ Vault: http://vault.example.com:8200
  └─ VAULT_TOKEN: hvs.prod-token (bootstrap only)
  └─ CLUSTER_NAME: prod-cluster
  └─ ENVIRONMENT: prod
  └─ Credentials: secret/gitops/prod/grafana-cloud
```

### Bootstrap Workflow Per Environment

```bash
# Admin bootstraps each cluster (separate commands)

# DEV CLUSTER
export VAULT_ADDR="http://vault.example.com:8200"
export VAULT_TOKEN="hvs.dev-token"
./bootstrap/setup-vault-integration.sh argo-cd
helm install argocd ... -f bootstrap/argocd/helm-values.yaml

# STAGING CLUSTER
export VAULT_ADDR="http://vault.example.com:8200"
export VAULT_TOKEN="hvs.staging-token"
./bootstrap/setup-vault-integration.sh argo-cd
helm install argocd ... -f bootstrap/argocd/helm-values.yaml

# PROD CLUSTER
export VAULT_ADDR="http://vault.example.com:8200"
export VAULT_TOKEN="hvs.prod-token"
./bootstrap/setup-vault-integration.sh argo-cd
helm install argocd ... -f bootstrap/argocd/helm-values.yaml
```

### Team Member Workflow (All Environments)

```bash
# No environment-specific setup needed!
# All clusters pull the same Git repository
# Each cluster authenticates with its own VAULT_TOKEN (stored in K8s)

# Team member workflow is identical across all environments:
git clone https://github.com/your-org/gitops-cluster-services.git
cd gitops-cluster-services

# Edit configurations
vi helmfile.yaml
vi releases/observability.yaml.gotmpl

# Push changes
git commit -m "Update monitoring config"
git push origin main

# Changes automatically synced to ALL clusters by their respective ArgoCD instances
# Each cluster uses its own Vault token from K8s secret
# Team member never touches Vault credentials!
```

## Secret Management Flow

### Admin Bootstrap (First Time)
```
Admin provides VAULT_TOKEN
         ↓
   ./setup-vault-integration.sh
         ↓
  Kubernetes Secret Created
  (argocd-vault-config)
         ↓
  ArgoCD Deployed
         ↓
  Helmfile plugin reads secret
         ↓
  External Secrets Operator pulls from Vault
         ↓
  Grafana Cloud credentials available to pods
```

### Team Member Deployment (After Bootstrap)
```
Team member: git push
         ↓
  ArgoCD detects change
         ↓
  Helmfile plugin reads from K8s secret
  (no env vars needed!)
         ↓
  External Secrets Operator pulls from Vault
  (using stored credentials)
         ↓
  New monitoring config deployed
         ↓
  Team member: git push (repeat)
```

## Practical Example: Adding a Team Member

### For Admin:

```bash
# No additional setup needed!
# The argocd-vault-config secret is already created
# Just give the new team member access to:
# 1. kubectl cluster (via kubeconfig)
# 2. Git repository (via GitHub)
```

### For New Team Member:

```bash
# 1. Get kubeconfig
kubectl config set-context prod-cluster

# 2. Clone repository
git clone https://github.com/your-org/gitops-cluster-services.git

# 3. Make changes (helmfile, values, manifests)
vi releases/observability.yaml.gotmpl

# 4. Commit and push
git commit -m "Update: add new service monitoring"
git push origin main

# That's it!
# No Vault credentials needed
# No VAULT_ADDR or VAULT_TOKEN needed
# ArgoCD handles everything
```

## Security Benefits

| Aspect | Environment Vars | Vault Integration |
|--------|------------------|-------------------|
| **Credential Exposure** | High risk (env vars visible) | Low risk (K8s secret) |
| **Team Onboarding** | Share credentials | Just share kubeconfig |
| **Credential Rotation** | Manual update everywhere | Rotate Vault token once |
| **Audit Trail** | Environment variable logs | Vault audit logs |
| **Multi-Environment** | Multiple env var sets | Single K8s secret per cluster |
| **Git Repository** | Credentials might leak | Never in Git |
| **Team Member Access** | Give Vault credentials | Give kubectl access only |

## Troubleshooting Team Issues

### Team Member: "I can't deploy changes"

**Check:**
```bash
# 1. Can they access the cluster?
kubectl auth can-i create applications -n argo-cd

# 2. Is their kubeconfig valid?
kubectl cluster-info

# 3. Is the ArgoCD application syncing?
kubectl get application -n argo-cd
```

### Team Member: "Credentials not working"

**They should NOT be dealing with credentials!**

Instead, check:
```bash
# Check if secret exists (admin only needs to verify this once)
kubectl get secret argocd-vault-config -n argo-cd

# Check if ExternalSecret is syncing (team member should report this)
kubectl get externalsecret -n monitoring
kubectl describe externalsecret grafana-cloud-credentials -n monitoring

# Check helmfile plugin logs
kubectl logs deployment/argocd-repo-server -n argo-cd -c helmfile-cmp
```

## Best Practices

1. **Rotate Vault Tokens Periodically**
   - Admin should rotate the token used in `argocd-vault-config`
   - Other team members are unaffected

2. **Keep Kubeconfig Secure**
   - Team members should protect their kubeconfig
   - It's equivalent to Vault access now

3. **Document Admin Processes**
   - Keep bootstrap procedures documented
   - In case you need to redeploy the cluster

4. **Monitor Vault Audit Logs**
   - Admin should review Vault audit logs
   - Verify only ArgoCD is accessing secrets

5. **Use RBAC for K8s Secrets**
   - Limit who can read `argocd-vault-config`
   - Only ArgoCD reposerver should need it

## Summary

**The Beauty of This Setup:**
- ✅ Vault credentials passed ONCE during bootstrap
- ✅ Stored securely in Kubernetes
- ✅ Team members never see Vault credentials
- ✅ Credentials never stored in Git
- ✅ One person manages bootstrap, everyone deploys

**Team members get:**
- Simple workflow (git push)
- No credential management
- No Vault access needed
- Full deployment capability

**Admin gets:**
- Centralized credential management
- Audit trail via Vault
- Easy credential rotation
- Security and compliance
