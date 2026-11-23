# GitOps Cluster Services

Production-ready GitOps repository for managing Kubernetes cluster platform services using Helmfile + ArgoCD.

## Overview

This repository deploys all cluster-wide backend services on an existing Kubernetes cluster:

- **Secrets Management**: External HashiCorp Vault + External Secrets Operator (syncs to K8s Secrets)
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
- External Vault instance (HA recommended for production)
- Grafana Cloud account

### Deploy Cluster Services

This repository is **environment-agnostic** — deploy the same cluster services to any Kubernetes cluster by setting environment variables.

#### 1. Set Required Environment Variables

```bash
export CLUSTER_NAME="my-cluster"           # Unique cluster identifier
export CLUSTER_DOMAIN="example.com"         # Domain for cluster services
export GITHUB_TOKEN="ghp_xxxx..."          # GitHub personal access token
export CLOUDFLARE_TOKEN="xxxx..."          # Cloudflare API token
export CLOUDFLARE_ACCOUNT_ID="xxxx..."     # Cloudflare account ID
export ARGOCD_ADMIN_PASSWORD_HASH="$2a..." # bcrypt hash of admin password
```

Generate bcrypt hash for ArgoCD password:
```bash
# Option 1: Using htpasswd
htpasswd -B -c temp.txt admin
cat temp.txt | awk -F: '{print $2}'

# Option 2: Using Python
python3 -c "import crypt; print(crypt.crypt('yourpassword', crypt.METHOD_BLOWFISH))"
```

#### 2. Set Optional Environment Variables (Recommended)

```bash
# External Vault
export EXTERNAL_VAULT_SERVER="https://vault.yourdomain.com"
export EXTERNAL_VAULT_AUTH_ROLE="default"

# Grafana Cloud
export GRAFANA_CLOUD_USERNAME="you@example.com"
export GRAFANA_CLOUD_PROM_URL="https://prometheus-blocks-prod-us-central1.grafana.net/api/prom/push"
export GRAFANA_CLOUD_PROM_PASSWORD="xxxx..."
export GRAFANA_CLOUD_LOKI_URL="https://logs-prod-us-central1.grafana.net/loki/api/v1/push"
export GRAFANA_CLOUD_LOKI_PASSWORD="xxxx..."

# Optional: Tempo for distributed tracing
export GRAFANA_CLOUD_TEMPO_URL="https://tempo-blocks-prod-us-central1.grafana.net:443"
export GRAFANA_CLOUD_TEMPO_PASSWORD="xxxx..."

# Deployment scaling
export CLOUDFLARED_REPLICAS="3"  # For HA deployments
```

#### 3. Deploy Cluster Services

**Option A: Direct Helmfile Deployment**

```bash
# Preview changes
helmfile template

# Deploy to cluster
helmfile sync
```

**Option B: Use ArgoCD (Recommended for GitOps)**

```bash
# Install ArgoCD first
kubectl create namespace argocd
helm repo add argoproj https://argoproj.github.io/argo-helm
helm install argocd argoproj/argo-cd \
  --namespace argocd \
  --values bootstrap/argocd/helm-values.yaml \
  --wait

# Deploy cluster services via ArgoCD
kubectl apply -f argocd/applications/app-of-apps.yaml

# Access ArgoCD
kubectl -n argocd port-forward svc/argocd-server 8080:443
# Open https://localhost:8080 in browser
```

See [BOOTSTRAP.md](./docs/BOOTSTRAP.md) for detailed bootstrap instructions.

## Environment Variables Reference

All cluster services are configured via environment variables. Set them before deploying:

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `CLUSTER_NAME` | ✓ | - | Unique cluster identifier (dev, staging, prod, etc) |
| `CLUSTER_DOMAIN` | ✓ | - | Domain for cluster services (e.g., example.com) |
| `GITHUB_TOKEN` | ✓ | - | GitHub personal access token |
| `CLOUDFLARE_TOKEN` | ✓ | - | Cloudflare API token |
| `CLOUDFLARE_ACCOUNT_ID` | ✓ | - | Cloudflare account ID |
| `ARGOCD_ADMIN_PASSWORD_HASH` | ✓ | - | bcrypt hash of ArgoCD admin password |
| `EXTERNAL_VAULT_SERVER` | ✗ | `https://vault.example.com` | External Vault server URL |
| `EXTERNAL_VAULT_PATH` | ✗ | `secret` | Vault KV path |
| `EXTERNAL_VAULT_AUTH_PATH` | ✗ | `kubernetes` | Vault Kubernetes auth method path |
| `EXTERNAL_VAULT_AUTH_ROLE` | ✗ | `default` | Vault Kubernetes auth role |
| `GRAFANA_CLOUD_USERNAME` | ✗ | `changeme` | Grafana Cloud username/email |
| `GRAFANA_CLOUD_PROM_URL` | ✗ | `https://prometheus-blocks-prod-us-central1.grafana.net/api/prom/push` | Grafana Cloud Prometheus endpoint |
| `GRAFANA_CLOUD_PROM_PASSWORD` | ✗ | `changeme` | Grafana Cloud Prometheus API token |
| `GRAFANA_CLOUD_LOKI_URL` | ✗ | `https://logs-prod-us-central1.grafana.net/loki/api/v1/push` | Grafana Cloud Loki endpoint |
| `GRAFANA_CLOUD_LOKI_PASSWORD` | ✗ | `changeme` | Grafana Cloud Loki API token |
| `GRAFANA_CLOUD_TEMPO_URL` | ✗ | `https://tempo-blocks-prod-us-central1.grafana.net:443` | Grafana Cloud Tempo endpoint |
| `GRAFANA_CLOUD_TEMPO_PASSWORD` | ✗ | `changeme` | Grafana Cloud Tempo API token |
| `CLOUDFLARED_REPLICAS` | ✗ | `1` | Number of Cloudflare Tunnel replicas |
| `AGENT_LOG_LEVEL` | ✗ | `info` | Grafana Agent log level |

## Architecture

### Design Pattern: App of Apps

```
gitops-cluster-services (this repo)
    ├── helmfile.yaml (orchestrates all releases - 3 environments)
    ├── releases/ (release definitions)
    │   ├── namespaces.yaml.gotmpl
    │   ├── vault.yaml.gotmpl (ESO → External Vault)
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
| **External Vault** | Secret management | External service (resilient) |
| **External Secrets** | Secret sync | External Vault ↔ K8s Secrets |
| **Grafana Agent** | Metrics/logs/traces collection | DaemonSet + StatefulSet |
| **Grafana Cloud** | Observability platform | Managed Prometheus, Loki, Tempo |
| **Cloudflare** | Ingress & DNS | Tunnel + DNS management |
| **External DNS** | Automatic DNS | Cloudflare integration |

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

## Deployment Patterns

Deploy the same cluster services to any environment by adjusting environment variables:

### Development Cluster
```bash
export CLUSTER_NAME="dev"
export CLUSTER_DOMAIN="dev.example.com"
export CLOUDFLARED_REPLICAS="1"
# ... set other required variables
helmfile sync
```

### Staging Cluster
```bash
export CLUSTER_NAME="staging"
export CLUSTER_DOMAIN="staging.example.com"
export CLOUDFLARED_REPLICAS="2"
# ... set other required variables
helmfile sync
```

### Production Cluster
```bash
export CLUSTER_NAME="prod"
export CLUSTER_DOMAIN="example.com"
export CLOUDFLARED_REPLICAS="3"
# ... set other required variables with production values
helmfile sync
```

All clusters deploy identical services — only configuration values differ.

## Key Features

### 🔐 Secrets Management
- **External Vault**: Resilient external service, survives cluster outages
- **Kubernetes auth**: Automatic pod authentication via ServiceAccount
- **External Secrets Operator**: Syncs secrets from Vault to Kubernetes Secrets
- **Rotation**: Automatic secret refresh (configurable)
- **Secret Zero**: No secrets in git; all stored in external Vault
- **Disaster Recovery**: Cluster-independent secrets ensure data safety

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

### Validate Configuration

Before deploying, validate your environment variables and Helmfile:

```bash
# Check that required environment variables are set
echo "CLUSTER_NAME: $CLUSTER_NAME"
echo "CLUSTER_DOMAIN: $CLUSTER_DOMAIN"
echo "GITHUB_TOKEN: ${GITHUB_TOKEN:0:10}..."  # Show only first 10 chars

# Render manifests to preview
helmfile template | head -100

# Validate with kubeconform
helmfile template | kubeconform -strict

# Lint YAML
yamllint releases/*.yaml.gotmpl
```

### Deploy All Services

Deploy cluster services with environment variables set:

```bash
# Set all required environment variables (see "Set Required Environment Variables" above)

# Preview changes
helmfile template

# Deploy to cluster
helmfile sync

# Or apply directly
helmfile template | kubectl apply -f -
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

All secrets are stored in your external Vault instance. To sync secrets to Kubernetes:

```bash
# Create ExternalSecret to sync from external Vault
kubectl apply -f - <<'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-db
  namespace: default
spec:
  secretStoreRef:
    name: vault  # References the ClusterSecretStore
    kind: ClusterSecretStore
  target:
    name: app-db  # Target Kubernetes Secret name
  data:
    - secretKey: username
      remoteRef:
        key: myapp/db      # Path in external Vault
        property: username # Property in secret
    - secretKey: password
      remoteRef:
        key: myapp/db
        property: password
EOF

# External Secrets Operator will automatically:
# - Authenticate to external Vault using Kubernetes auth
# - Fetch secrets from your Vault instance
# - Create/update the Kubernetes Secret
# - Refresh secrets on configured intervals
```

**Note**: The ClusterSecretStore is pre-configured in the `vault-secretstore` release to connect to your external Vault using Kubernetes authentication.

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
│   ├── vault.yaml.gotmpl (External Secrets Operator for external Vault)
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

### Configure External Vault (Required)

To connect to your external Vault instance:

1. Set up external Vault (standalone, HA cluster, or managed service)
2. Enable Kubernetes auth method in Vault:
   ```bash
   vault auth enable kubernetes
   vault write auth/kubernetes/config \
     kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT" \
     kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
     token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
   
   # Create a role for External Secrets Operator
   vault write auth/kubernetes/role/default \
     bound_service_account_names=external-secrets-vault \
     bound_service_account_namespaces=external-secrets \
     policies=default
   ```
3. Update `helmfile.yaml` for each environment:
   ```yaml
   externalVault:
     server: "https://vault.yourdomain.com"  # Your Vault server URL
     path: "secret"  # KV v2 path
     version: "v2"
     authPath: "kubernetes"
     authRole: "default"  # Must match role created above
   ```
4. Commit and push
5. ArgoCD deploys External Secrets Operator configured for external Vault

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
