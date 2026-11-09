# GitOps Cluster Services

Production-ready GitOps repository for managing Kubernetes cluster platform services using Helmfile + ArgoCD.

## Overview

This repository deploys all cluster-wide backend services on an existing Kubernetes cluster:

- **Secrets Management**: In-cluster HashiCorp Vault + External Secrets Operator
- **Observability**: Prometheus, Grafana Cloud, Loki, Tempo, Thanos
- **Security**: Kyverno policies, Falco runtime security, Trivy vulnerability scanning
- **Networking**: Cloudflare Tunnel for ingress, External DNS for Cloudflare DNS
- **GitOps**: ArgoCD with Helmfile plugin for declarative management

## Quick Start

### Prerequisites

- Existing Kubernetes cluster (1.24+)
- `kubectl` configured to access cluster
- `helm` 3.12+
- `helmfile` 0.144+
- GitHub account with personal access token
- Cloudflare account with API token

### Bootstrap

1. **Clone this repository**:
   ```bash
   git clone https://github.com/draju1980/gitops-cluster-services.git
   cd gitops-cluster-services
   ```

2. **Create secrets** (see [BOOTSTRAP.md](./docs/BOOTSTRAP.md)):
   ```bash
   export GITHUB_TOKEN="ghp_xxxx..."
   export CLOUDFLARE_TOKEN="xxxx..."
   export CLOUDFLARE_ACCOUNT_ID="xxxx..."
   ```

3. **Install ArgoCD**:
   ```bash
   kubectl create namespace argocd
   helm repo add argoproj https://argoproj.github.io/argo-helm
   helm install argocd argoproj/argo-cd \
     --namespace argocd \
     --values bootstrap/argocd/helm-values.yaml \
     --wait
   ```

4. **Deploy root application** (applies all platform services):
   ```bash
   kubectl apply -f argocd/applications/app-of-apps.yaml
   ```

5. **Access ArgoCD**:
   ```bash
   kubectl -n argocd port-forward svc/argocd-server 8080:443
   # Open https://localhost:8080 in browser
   ```

See [BOOTSTRAP.md](./docs/BOOTSTRAP.md) for detailed bootstrap instructions.

## Architecture

### Design Pattern: App of Apps

```
gitops-cluster-services (this repo)
    ├── helmfile.yaml (orchestrates all releases)
    ├── releases/ (release definitions)
    │   ├── namespaces.yaml.gotmpl
    │   ├── vault.yaml.gotmpl
    │   ├── security.yaml.gotmpl
    │   ├── observability.yaml.gotmpl
    │   ├── networking.yaml.gotmpl
    │   └── argocd.yaml.gotmpl
    ├── argocd/
    │   ├── projects/ (RBAC projects)
    │   │   ├── platform.yaml
    │   │   ├── security.yaml
    │   │   ├── observability.yaml
    │   │   └── networking.yaml
    │   └── applications/
    │       └── app-of-apps.yaml (root application)
    └── vault/ (vault integration examples)
        ├── auth.yaml
        ├── secretstore.yaml
        └── externalsecret-example.yaml
```

### Technology Stack

| Component | Purpose | Status |
|-----------|---------|--------|
| **Helmfile** | Release orchestration | Single source of truth |
| **ArgoCD** | GitOps deployment | Auto-sync, prune, self-heal enabled |
| **Vault** | Secret management | In-cluster, HA with Raft |
| **Kyverno** | Policy engine | Pod security, network policies |
| **Falco** | Runtime security | Threat detection |
| **Trivy** | Vulnerability scanning | Image & config scanning |
| **Prometheus** | Metrics collection | Retention: 24h-30d (env dependent) |
| **Grafana Cloud** | Visualization & alerting | Remote backend |
| **Loki** | Log aggregation | S3-compatible storage |
| **Tempo** | Distributed tracing | OTLP receiver enabled |
| **Thanos** | Long-term metrics | Object storage querying |
| **Cloudflare** | Ingress & DNS | Tunnel for ingress, DNS management |
| **External DNS** | Automatic DNS | Cloudflare integration |
| **External Secrets** | Secret sync | Vault ↔ Kubernetes |

### Data Flow

```
Developer commits to gitops-cluster-services
    ↓
GitHub webhook notifies ArgoCD
    ↓
ArgoCD pulls repo changes
    ↓
CMP plugin renders: helmfile -e <env> template
    ↓
Generated manifests passed to kubectl apply (server-side)
    ↓
Auto-sync + Self-heal applies changes
    ↓
Prune removes deleted resources
    ↓
Observability captures metrics/logs/traces
```

## Deployment Environments

Three environments supported with different configurations:

### Development (`helmfile -e dev`)
- Single replica services
- Vault in standalone mode
- Kyverno in **Audit** mode (logs violations)
- 24h metric retention
- No notifications

### Staging (`helmfile -e staging`)
- 2 replicas for HA
- Vault with 2-node Raft
- Kyverno in **Audit** mode
- 72h metric retention
- Slack notifications enabled

### Production (`helmfile -e prod`)
- 3+ replicas for full HA
- Vault with 3-node Raft
- Kyverno in **Enforce** mode (blocks violations)
- 30-day metric retention
- Full observability

## Key Features

### 🔐 Secrets Management
- **In-cluster Vault**: No external dependency
- **Kubernetes auth**: Automatic pod authentication
- **External Secrets Operator**: Keeps Kubernetes Secrets in sync with Vault
- **Rotation**: Automatic secret refresh every 15 minutes

### 🛡️ Security
- **Kyverno**: Enforce pod security standards, resource limits, image policies
- **Falco**: Real-time runtime threat detection
- **Trivy**: Automated vulnerability scanning
- **Network Policies**: Default-deny with explicit allow-lists
- **RBAC**: Project-level access control

### 📊 Observability
- **Prometheus**: Scrapes cluster metrics
- **Grafana Cloud**: Managed visualization
- **Loki**: Log aggregation to Grafana Cloud
- **Tempo**: Distributed tracing with OTLP
- **Thanos**: Long-term metrics storage

### 🌐 Networking
- **Cloudflare Tunnel**: Expose cluster without public IPs
- **External DNS**: Automatic Cloudflare DNS management
- **No Ingress Controller**: Cloudflare handles all ingress routing

### 🚀 GitOps
- **Helmfile + ArgoCD**: Single source of truth
- **CMP Plugin**: Helmfile rendering in ArgoCD
- **Auto-Sync**: Changes deployed automatically
- **Self-Heal**: Drift corrected automatically
- **Prune**: Deleted resources removed

## Usage

### Validate Helmfile

```bash
# Render manifests for an environment
helmfile -e dev template | head -50

# Validate with kubeconform
helmfile -e prod template | kubeconform -strict

# Lint YAML
yamllint releases/*.yaml.gotmpl
```

### Deploy Changes

1. **Edit release or values**
2. **Commit to git**:
   ```bash
   git add .
   git commit -m "Update Prometheus retention"
   git push origin main
   ```
3. **ArgoCD auto-syncs** within 3 minutes
4. **Monitor in ArgoCD UI**: https://argo-cd.cluster.domain

###  Manage Vault Secrets

```bash
# Create a secret
kubectl -n vault exec -it vault-0 -- vault kv put secret/myapp/db \
  username=admin password=secret

# Create ExternalSecret to sync it
kubectl apply -f - <<'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-db
  namespace: default
spec:
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: app-db
  data:
    - secretKey: username
      remoteRef:
        key: myapp/db
        property: username
EOF
```

### Monitor Observability

```bash
# Prometheus
kubectl -n monitoring port-forward svc/prometheus-operated 9090:9090
# Visit http://localhost:9090

# Grafana
kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-grafana 3000:80
# Visit http://localhost:3000 (default: admin/prom-operator)
```

### Check Kyverno Policies

```bash
# View policy violations (in audit mode)
kubectl get clusterpolicyreports -A

# View policies
kubectl get clusterpolicies

# Temporarily switch to audit mode
# Edit helmfile.yaml and change:
# kyverno.validationFailureAction: "audit"
helmfile -e prod apply
```

## Documentation

- **[ARCHITECTURE.md](./docs/ARCHITECTURE.md)**: Detailed architecture, design decisions, integration patterns
- **[BOOTSTRAP.md](./docs/BOOTSTRAP.md)**: Step-by-step bootstrap guide, Vault setup, troubleshooting
- **[OPERATING_MODEL.md](./docs/OPERATING_MODEL.md)**: Day-2 operations, maintenance tasks, incident response

## Repository Structure

```
gitops-cluster-services/
├── README.md (this file)
├── helmfile.yaml (main orchestration file)
├── releases/ (helm release definitions)
│   ├── namespaces.yaml.gotmpl
│   ├── vault.yaml.gotmpl
│   ├── security.yaml.gotmpl
│   ├── ingress.yaml.gotmpl (external-dns only)
│   ├── observability.yaml.gotmpl
│   ├── networking.yaml.gotmpl (cloudflare tunnel)
│   └── argocd.yaml.gotmpl
├── argocd/
│   ├── projects/ (AppProject RBAC)
│   │   ├── platform.yaml
│   │   ├── security.yaml
│   │   ├── observability.yaml
│   │   └── networking.yaml
│   └── applications/
│       └── app-of-apps.yaml (root application)
├── bootstrap/
│   └── argocd/
│       ├── helm-values.yaml (bootstrap install values)
│       └── install.sh (bootstrap script)
├── vault/ (vault integration examples)
│   ├── auth.yaml (kubernetes auth setup)
│   ├── secretstore.yaml (ClusterSecretStore config)
│   └── externalsecret-example.yaml (example ExternalSecret)
├── security/ (security policy examples)
├── docs/
│   ├── ARCHITECTURE.md
│   ├── BOOTSTRAP.md
│   ├── OPERATING_MODEL.md
│   └── TROUBLESHOOTING.md
└── .gitignore
```

## Customization

### Update Chart Versions

```bash
# Check available versions
helm search repo <chart> --versions

# Update helmfile.yaml
# Redeploy via ArgoCD (auto-sync will apply)
```

### Modify Environment Values

Edit `helmfile.yaml` and update the environment-specific values:

```yaml
environments:
  prod:
    values:
      - vault:
          replicas: 5  # Increase replicas
```

### Add New Release

1. Create `releases/myservice.yaml.gotmpl`
2. Add to `helmfile.yaml` helmfiles section
3. Commit and push
4. ArgoCD deploys automatically

## Troubleshooting

See [OPERATING_MODEL.md](./docs/OPERATING_MODEL.md#troubleshooting) for common issues:
- ArgoCD stuck "Progressing"
- Vault authentication failing
- Kyverno blocking deployments
- Metrics not appearing in Prometheus

## Security

### Secret Management
- No secrets committed to git
- All secrets stored in Vault
- Automatic rotation via External Secrets
- Audit logging for all secret access

### RBAC
- ArgoCD projects restrict source repos and destinations
- Kyverno enforces pod security standards
- Network policies default-deny with explicit allows

### Compliance
- Audit logging (Falco, Vault, Kyverno)
- Vulnerability scanning (Trivy)
- Policy enforcement (Kyverno)
- Network segmentation (NetworkPolicies)

## Contributing

1. Create a feature branch
2. Make changes
3. Test locally: `helmfile -e dev template`
4. Commit with clear message
5. Push and create PR

All changes are validated by:
- yamllint for YAML syntax
- helmfile template rendering
- kubeconform for Kubernetes schema compliance

## Support & References

- **ArgoCD Docs**: https://argo-cd.readthedocs.io/
- **Helmfile Docs**: https://helmfile.readthedocs.io/
- **Vault Docs**: https://www.vaultproject.io/docs/
- **Kyverno Docs**: https://kyverno.io/docs/
- **External Secrets**: https://external-secrets.io/
- **Cloudflare Docs**: https://developers.cloudflare.com/

## License

[Specify your license]

## Ownership

- **Maintained by**: [Your team]
- **Contact**: [Email or Slack channel]
- **On-call**: [Rotation or team responsible for incidents]
