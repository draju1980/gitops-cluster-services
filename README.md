# GitOps Cluster Services

Production-ready GitOps repository for managing Kubernetes cluster platform services using Helmfile + ArgoCD.

## Overview

This repository deploys all cluster-wide backend services on an existing Kubernetes cluster:

- **Secrets Management**: In-cluster HashiCorp Vault + External Secrets Operator
- **Observability**: Grafana Cloud (Prometheus, Loki, Tempo) with Grafana Agent for collection
- **Networking**: Cloudflare Tunnel for ingress, External DNS for Cloudflare DNS
- **GitOps**: ArgoCD with Helmfile plugin for declarative management
- **Minimal & Clean**: No security tools forced; users add Kyverno, Falco, Trivy as needed

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

## Direct Helmfile Deployment (Without ArgoCD)

If you prefer to deploy without ArgoCD, use Helmfile directly:

```bash
# Dry-run to preview changes
helmfile -e prod template

# Apply to cluster
helmfile -e prod apply

# Or render and apply with kubectl
helmfile -e prod template | kubectl apply -f -

# Sync with dependencies and hooks
helmfile -e prod sync
```

**Note**: Direct Helmfile deployment doesn't provide ArgoCD features like auto-sync, drift detection, or rollback. See [BOOTSTRAP.md](./docs/BOOTSTRAP.md) for the recommended GitOps approach using ArgoCD.

## Architecture

### Design Pattern: App of Apps

```
gitops-cluster-services (this repo)
    ├── helmfile.yaml (orchestrates all releases - 3 environments)
    ├── releases/ (release definitions)
    │   ├── namespaces.yaml.gotmpl
    │   ├── vault.yaml.gotmpl (in-cluster Vault + ESO)
    │   ├── observability.yaml.gotmpl (Grafana Agent → Grafana Cloud)
    │   ├── ingress.yaml.gotmpl (External DNS)
    │   ├── networking.yaml.gotmpl (Cloudflare Tunnel)
    │   └── argocd.yaml.gotmpl (ArgoCD with Helmfile CMP)
    ├── argocd/
    │   ├── projects/ (3 RBAC projects)
    │   │   ├── platform.yaml (core services)
    │   │   ├── observability.yaml (monitoring)
    │   │   └── networking.yaml (Cloudflare/DNS)
    │   └── applications/
    │       └── app-of-apps.yaml (root application)
    ├── vault/ (vault integration examples)
    │   ├── auth.yaml
    │   ├── secretstore.yaml
    │   └── externalsecret-example.yaml
    └── docs/ (complete documentation)
        ├── ARCHITECTURE.md
        ├── BOOTSTRAP.md
        └── OPERATING_MODEL.md
```

### Technology Stack

| Component | Purpose | Deployment |
|-----------|---------|----------|
| **Helmfile** | Release orchestration | Single source of truth |
| **ArgoCD** | GitOps deployment | Auto-sync, prune, self-heal |
| **Vault** | Secret management | In-cluster, HA with Raft |
| **Grafana Agent** | Metrics/logs/traces collection | DaemonSet + StatefulSet |
| **Grafana Cloud** | Observability platform | Managed Prometheus, Loki, Tempo |
| **Cloudflare** | Ingress & DNS | Tunnel + DNS management |
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
- Grafana Agent in minimal config
- Grafana Cloud metrics/logs/traces stored by plan
- No Slack notifications

### Staging (`helmfile -e staging`)
- 2 replicas for HA
- Vault with 2-node Raft
- Grafana Agent for enhanced collection
- Grafana Cloud with staging retention policy
- Slack notifications enabled

### Production (`helmfile -e prod`)
- 3+ replicas for full HA
- Vault with 3-node Raft
- Grafana Agent with comprehensive monitoring
- Grafana Cloud with extended retention
- Full observability and alerting

## Key Features

### 🔐 Secrets Management
- **In-cluster Vault**: No external dependency, HA-ready with Raft storage
- **Kubernetes auth**: Automatic pod authentication
- **External Secrets Operator**: Keeps Kubernetes Secrets in sync with Vault
- **Rotation**: Automatic secret refresh every 15 minutes
- **Secret Zero**: No secrets in git; only placeholders

### 📊 Observability - Grafana Cloud
- **Grafana Agent**: Collects metrics, logs, and traces from cluster
- **Prometheus**: Hosted in Grafana Cloud for metrics collection
- **Loki**: Hosted in Grafana Cloud for log aggregation
- **Tempo**: Hosted in Grafana Cloud for distributed tracing
- **Zero Local Storage**: No PVCs needed for observability; fully managed service
- **Auto-scaling**: Grafana Cloud handles retention and scaling automatically

### 🌐 Networking
- **Cloudflare Tunnel**: Expose cluster without public IPs
- **External DNS**: Automatic Cloudflare DNS management
- **No Ingress Controller**: Cloudflare Tunnel handles all ingress routing
- **No TLS Management**: Cloudflare manages TLS certificates

### 🚀 GitOps
- **Helmfile + ArgoCD**: Single source of truth
- **CMP Plugin**: Helmfile rendering in ArgoCD
- **Auto-Sync**: Changes deployed automatically
- **Self-Heal**: Drift corrected automatically
- **Prune**: Deleted resources removed
- **3 Environments**: dev, staging, prod with different configs

### 🎯 Minimal & Clean
- **No Security Tools Forced**: Users add Kyverno, Falco, Trivy as needed
- **Production-Ready Baseline**: All critical services included
- **Easy to Extend**: Clear patterns for adding new services

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

### Deploy All Services (via Helmfile)

To deploy all cluster services directly using Helmfile:

```bash
# For development environment
helmfile -e dev template | kubectl apply -f -

# For staging environment
helmfile -e staging template | kubectl apply -f -

# For production environment
helmfile -e prod template | kubectl apply -f -
```

### Deploy Changes (via ArgoCD - Recommended)

1. **Edit release or values**
2. **Commit to git**:
   ```bash
   git add .
   git commit -m "Update Prometheus retention"
   git push origin master
   ```
3. **ArgoCD auto-syncs** within 3 minutes (or manually sync via UI)
4. **Monitor in ArgoCD UI**: https://argo-cd.{clusterName}.{domain}

**Recommended**: Use ArgoCD for automatic syncing, drift detection, and rollback capabilities.

### Manage Vault Secrets

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

All observability is handled by Grafana Cloud. To view metrics, logs, and traces:

1. **Access Grafana Cloud**:
   - Visit your Grafana Cloud instance at: `https://<your-instance>.grafana.net`
   - Log in with your Grafana Cloud credentials

2. **Check Grafana Agent Status**:
   ```bash
   # View Grafana Agent deployment
   kubectl -n monitoring get deployment grafana-agent
   kubectl -n monitoring get logs -f deployment/grafana-agent
   
   # View Grafana Agent StatefulSet for node metrics
   kubectl -n monitoring get statefulset grafana-agent-node
   kubectl -n monitoring logs -f statefulset/grafana-agent-node
   ```

3. **Verify Data is Being Collected**:
   - In Grafana Cloud, check the **Explore** tab for metrics, logs, and traces
   - Look for dashboards automatically created for Kubernetes monitoring

## Documentation

- **[ARCHITECTURE.md](./docs/ARCHITECTURE.md)**: Detailed architecture, design decisions, integration patterns
- **[BOOTSTRAP.md](./docs/BOOTSTRAP.md)**: Step-by-step bootstrap guide, Vault setup, troubleshooting
- **[OPERATING_MODEL.md](./docs/OPERATING_MODEL.md)**: Day-2 operations, maintenance tasks, incident response

## Repository Structure

```
gitops-cluster-services/
├── README.md (this file)
├── helmfile.yaml (main orchestration - dev/staging/prod environments)
├── releases/ (helm release definitions)
│   ├── namespaces.yaml.gotmpl (9 namespaces)
│   ├── vault.yaml.gotmpl (Vault + External Secrets Operator)
│   ├── observability.yaml.gotmpl (Grafana Agent for Grafana Cloud)
│   ├── ingress.yaml.gotmpl (External DNS only)
│   ├── networking.yaml.gotmpl (Cloudflare Tunnel)
│   └── argocd.yaml.gotmpl (ArgoCD with Helmfile CMP plugin)
├── argocd/
│   ├── projects/ (3 AppProject RBAC)
│   │   ├── platform.yaml (core infrastructure)
│   │   ├── observability.yaml (monitoring & logging)
│   │   └── networking.yaml (Cloudflare & DNS)
│   └── applications/
│       └── app-of-apps.yaml (root application)
├── bootstrap/
│   └── argocd/
│       ├── helm-values.yaml (ArgoCD bootstrap values)
│       └── install.sh (placeholder for bootstrap script)
├── vault/ (Vault integration examples)
│   ├── auth.yaml (Kubernetes auth method setup)
│   ├── secretstore.yaml (ClusterSecretStore configuration)
│   └── externalsecret-example.yaml (example ExternalSecret usage)
├── docs/ (complete documentation)
│   ├── ARCHITECTURE.md (design decisions, patterns)
│   ├── BOOTSTRAP.md (step-by-step deployment guide)
│   └── OPERATING_MODEL.md (day-2 operations, troubleshooting)
├── .gitignore (excludes .claude/ and common files)
└── .git/ (git repository)
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
          storageSize: "100Gi"
        prometheus:
          retention: "90d"
```

### Add New Release

1. Create `releases/myservice.yaml.gotmpl`
2. Add to `helmfile.yaml` helmfiles section
3. Commit and push
4. ArgoCD deploys automatically

### Configure Grafana Cloud Endpoints (Required)

To connect to Grafana Cloud:

1. Create a Grafana Cloud instance at https://grafana.com/cloud/
2. Get your credentials:
   - Username (usually "username@example.com")
   - Grafana Cloud API tokens for Prometheus, Loki, and Tempo
   - Regional endpoints (replace `us-central1` in helmfile.yaml if needed)
3. Update `helmfile.yaml` for each environment:
   ```yaml
   grafanaCloud:
     username: "your-email@example.com"
     prometheusUrl: "https://prometheus-blocks-prod-us-central1.grafana.net/api/prom/push"
     prometheusPassword: "your-api-token"
     lokiUrl: "https://logs-prod-us-central1.grafana.net/loki/api/v1/push"
     lokiPassword: "your-api-token"
   ```
4. Commit and push
5. ArgoCD deploys Grafana Agent with Grafana Cloud configuration

## Troubleshooting

See [OPERATING_MODEL.md](./docs/OPERATING_MODEL.md#troubleshooting) for common issues:
- ArgoCD stuck "Progressing"
- Vault authentication failing
- Metrics not appearing in Prometheus
- Storage volume issues

## Security

### Secret Management
- No secrets committed to git
- All secrets stored in Vault
- Automatic rotation via External Secrets
- Audit logging for all secret access

### Network & Access
- Cloudflare Tunnel for secure cluster access
- No public ingress IPs exposed
- Private Kubernetes API access only
- ClusterSecretStore RBAC controls

### Compliance
- Local storage with encrypted PVCs (user configured)
- Optional S3 storage with encryption (user configured)
- Audit logging via Vault and Kubernetes API server
- Resource limits and requests enforced

## Contributing

1. Create a feature branch
2. Make changes
3. Test locally: `helmfile -e dev template`
4. Commit with draju1980 profile
5. Push and create PR

All changes are validated by:
- yamllint for YAML syntax
- helmfile template rendering
- kubeconform for Kubernetes schema compliance

## Support & References

- **ArgoCD Docs**: https://argo-cd.readthedocs.io/
- **Helmfile Docs**: https://helmfile.readthedocs.io/
- **Vault Docs**: https://www.vaultproject.io/docs/
- **External Secrets**: https://external-secrets.io/
- **Cloudflare Docs**: https://developers.cloudflare.com/

## License

MIT

## Ownership

- **Maintained by**: draju1980
- **GitHub**: https://github.com/draju1980/gitops-cluster-services
- **Contact**: For issues and questions, use GitHub issues
