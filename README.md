# GitOps Cluster Services

Production-ready, minimal Kubernetes cluster infrastructure module using Helmfile + ArgoCD.

## Overview

This repository deploys essential cluster-wide platform services on any Kubernetes cluster using **Helmfile** as a reusable module:

- **Observability**: Grafana Cloud Alloy agent for metrics, logs, and traces collection
- **Networking**: Cloudflare Tunnel for secure ingress without public IPs
- **GitOps**: ArgoCD with Helmfile plugin for declarative infrastructure
- **Minimal**: Only 4 essential releases; no forced dependencies

## Quick Start

### Prerequisites

- Kubernetes cluster (1.24+)
- `kubectl`, `helm` (3.12+), `helmfile` (0.144+)
- GitHub personal access token
- Cloudflare account with API token and account ID
- Grafana Cloud account with regional endpoints

### Deploy

This is a reusable module — set environment variables and deploy to any Kubernetes cluster:

```bash
# Set cluster configuration
export CLUSTER_NAME="dev"                    # Cluster identifier
export CLUSTER_DOMAIN="example.com"          # Domain for services
export CLOUDFLARED_REPLICAS="1"              # (optional, default: 1)

# Set secrets
export GITHUB_TOKEN="ghp_xxxx..."            # GitHub PAT
export CLOUDFLARE_TOKEN="xxxx..."            # Cloudflare API token
export CLOUDFLARE_ACCOUNT_ID="xxxx..."       # Cloudflare account ID
export ARGOCD_ADMIN_PASSWORD_HASH="$2a$10$..." # bcrypt hash

# Set Grafana Cloud configuration (environment-specific)
export GRAFANA_CLOUD_TOKEN="xxx"
export GRAFANA_CLOUD_PROM_URL="https://prometheus-prod-43-prod-ap-south-1.grafana.net/api/prom/push"
export GRAFANA_CLOUD_PROM_USER="123456"
export GRAFANA_CLOUD_LOKI_URL="https://logs-prod-028.grafana.net/loki/api/v1/push"
export GRAFANA_CLOUD_LOKI_USER="123456"
export GRAFANA_CLOUD_TEMPO_URL="tempo-prod-19-prod-ap-south-1.grafana.net:443"
export GRAFANA_CLOUD_TEMPO_USER="123456"

# Preview
helmfile template | head -100

# Deploy
helmfile sync
```

## Environment-Specific Deployment

Same code, different environments. Just override variables:

```bash
# Dev
export CLUSTER_NAME="dev" CLUSTER_DOMAIN="dev.example.com" CLOUDFLARED_REPLICAS="1"
export GRAFANA_CLOUD_PROM_URL="..." GRAFANA_CLOUD_PROM_USER="..." # dev Grafana
helmfile sync

# Staging
export CLUSTER_NAME="staging" CLUSTER_DOMAIN="staging.example.com" CLOUDFLARED_REPLICAS="2"
export GRAFANA_CLOUD_PROM_URL="..." GRAFANA_CLOUD_PROM_USER="..." # staging Grafana
helmfile sync

# Production
export CLUSTER_NAME="prod" CLUSTER_DOMAIN="example.com" CLOUDFLARED_REPLICAS="3"
export GRAFANA_CLOUD_PROM_URL="..." GRAFANA_CLOUD_PROM_USER="..." # prod Grafana
helmfile sync
```

## Architecture

### Minimal Stack (4 Releases)

```
helmfile.yaml                    
├── releases/namespaces.yaml      → Create monitoring namespace
├── releases/observability.yaml   → Grafana Cloud Alloy agent
├── releases/networking.yaml      → Cloudflare Tunnel controller
└── releases/argocd.yaml          → ArgoCD deployment
```

### Helm Repositories (3 only)

| Repo | Purpose |
|------|---------|
| `argoproj` | ArgoCD |
| `grafana` | Grafana Alloy |
| `strrl.dev` | Cloudflare Tunnel |

### Data Flow

```
Kubernetes Cluster
    ↓
Grafana Alloy Agent (pod)
    ├── Scrapes metrics → Grafana Cloud Prometheus
    ├── Collects logs → Grafana Cloud Loki
    └── Receives traces → Grafana Cloud Tempo
    ↓
Cloudflare Tunnel
    └── Routes ingress traffic securely
    ↓
ArgoCD
    └── Manages all deployments declaratively
```

## Components

### 🚀 Grafana Cloud Alloy (`observability.yaml`)

**Lightweight metrics/logs/traces collection**

- Discovers and scrapes all Kubernetes pods, nodes, services
- Collects container logs via log file reading
- Receives OTLP traces on ports 4317 (gRPC) and 4318 (HTTP)
- Sends everything to Grafana Cloud (configurable endpoints)
- Resource-efficient: 200m CPU, 256Mi memory

```yaml
Prometheus scraping:
  - job: kubernetes-pods (30s interval)
  - job: kubernetes-nodes (30s interval)
  - job: kubernetes-services (30s interval)

Logs collection:
  - All container logs from all pods

Traces reception:
  - gRPC: 0.0.0.0:4317
  - HTTP: 0.0.0.0:4318
```

### 🌐 Cloudflare Tunnel (`networking.yaml`)

**Secure ingress without public IPs**

- Establishes outbound-only tunnel to Cloudflare
- Routes all ingress through Cloudflare
- No TLS management needed (handled by Cloudflare)
- Configurable cloudflared replicas for HA

### 🔑 ArgoCD (`argocd.yaml`)

**GitOps continuous deployment**

- Monitors GitHub repository for changes
- Uses Helmfile plugin for rendering
- Auto-syncs to cluster
- Self-heals drift
- Web UI for visibility and manual operations

### 📦 Namespaces (`namespaces.yaml`)

Creates required namespaces:
- `argo-cd` (ArgoCD)
- `monitoring` (Alloy, metrics)
- `cloudflare` (Cloudflare Tunnel)

## Environment Variables

| Variable | Required | Purpose |
|----------|----------|---------|
| `CLUSTER_NAME` | ✓ | Unique cluster ID (dev, staging, prod) |
| `CLUSTER_DOMAIN` | ✓ | Domain for services |
| `GITHUB_TOKEN` | ✓ | GitHub personal access token |
| `CLOUDFLARE_TOKEN` | ✓ | Cloudflare API token |
| `CLOUDFLARE_ACCOUNT_ID` | ✓ | Cloudflare account ID |
| `ARGOCD_ADMIN_PASSWORD_HASH` | ✓ | bcrypt hash of ArgoCD password |
| `GRAFANA_CLOUD_TOKEN` | ✓ | Grafana Cloud API token |
| `GRAFANA_CLOUD_PROM_URL` | ✓ | Prometheus remote write URL |
| `GRAFANA_CLOUD_PROM_USER` | ✓ | Prometheus username |
| `GRAFANA_CLOUD_LOKI_URL` | ✓ | Loki push URL |
| `GRAFANA_CLOUD_LOKI_USER` | ✓ | Loki username |
| `GRAFANA_CLOUD_TEMPO_URL` | ✓ | Tempo endpoint |
| `GRAFANA_CLOUD_TEMPO_USER` | ✓ | Tempo username |
| `CLOUDFLARED_REPLICAS` | ✗ | Cloudflare replicas (default: 1) |

### Generate ArgoCD Password Hash

```bash
# Option 1: htpasswd
htpasswd -B -c temp.txt admin
cat temp.txt | awk -F: '{print $2}'

# Option 2: Python
python3 -c "import crypt; print(crypt.crypt('yourpassword', crypt.METHOD_BLOWFISH))"
```

## Usage

### Validate Helmfile

```bash
# Check required env vars
echo "CLUSTER_NAME=$CLUSTER_NAME CLUSTER_DOMAIN=$CLUSTER_DOMAIN"

# Render manifests
helmfile template | head -50

# Validate with kubeconform
helmfile template | kubeconform -strict

# Lint YAML
yamllint releases/*.yaml.gotmpl
```

### Deploy

```bash
# Set all environment variables first (see Quick Start)

# Preview
helmfile diff

# Deploy
helmfile sync

# Check status
kubectl get pods -A
kubectl get ingress -A
```

### Monitor

```bash
# Check Alloy status
kubectl get pods -n monitoring

# View Alloy logs
kubectl logs -n monitoring -l app=alloy -f

# Check metrics in Grafana Cloud
# Dashboard: https://your-instance.grafana.net/d/kubernetes

# Access ArgoCD UI
kubectl port-forward -n argo-cd svc/argo-cd-server 8080:443
# https://localhost:8080 (password from ARGOCD_ADMIN_PASSWORD_HASH)
```

## Deployment Examples

### Deploy to Multiple Orgs/Teams

Each team can use cluster-services with their own configuration:

```bash
# Team A (Grafana Cloud instance in US)
export GRAFANA_CLOUD_PROM_URL="https://prometheus-prod-43-prod-us-central1.grafana.net/api/prom/push"
helmfile sync

# Team B (Grafana Cloud instance in EU)
export GRAFANA_CLOUD_PROM_URL="https://prometheus-prod-55-prod-eu-west-1.grafana.net/api/prom/push"
helmfile sync
```

### Deploy with ArgoCD (Recommended)

```bash
# Create ArgoCD application pointing to this repo
kubectl apply -f - <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cluster-services
  namespace: argo-cd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-cluster-services.git
    targetRevision: main
    path: .
    plugin:
      name: helmfile
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF
```

## Customization

### Add New Release

1. Create `releases/myservice.yaml.gotmpl`
2. Add to `helmfile.yaml` helmfiles section
3. Commit and push
4. ArgoCD deploys automatically

### Update Chart Versions

Edit release version in `releases/*.yaml.gotmpl` and push. ArgoCD syncs automatically.

### Override Values per Environment

Extend `helmfile.yaml` environments section:

```yaml
environments:
  prod:
    values:
      - clusterName: prod
        cloudflared:
          replicaCount: 3
```

## Troubleshooting

### Alloy not collecting metrics

```bash
# Check pod status
kubectl get pods -n monitoring

# View logs
kubectl logs -n monitoring -l app=alloy

# Check configuration
kubectl get configmap -n monitoring alloy-config -o yaml

# Verify network connectivity to Grafana Cloud
kubectl exec -it -n monitoring <pod-name> -- \
  curl -v https://prometheus-prod-43-prod-ap-south-1.grafana.net/api/prom/push
```

### ArgoCD not syncing

```bash
# Check ArgoCD status
kubectl get application -n argo-cd

# View ArgoCD logs
kubectl logs -n argo-cd -l app.kubernetes.io/name=argocd-application-controller -f

# Check if Helmfile plugin is working
kubectl get configmap -n argo-cd argocd-cmp-plugins -o yaml
```

### Cloudflare Tunnel not routing

```bash
# Check cloudflared status
kubectl get pods -n cloudflare

# View tunnel logs
kubectl logs -n cloudflare -l app=cloudflare-tunnel-ingress-controller -f

# Verify DNS in Cloudflare dashboard
```

## Repository Structure

```
cluster-services/
├── helmfile.yaml.gotmpl           # Main orchestration
├── releases/                       # 4 essential releases
│   ├── namespaces.yaml.gotmpl
│   ├── observability.yaml.gotmpl  # Grafana Alloy
│   ├── networking.yaml.gotmpl     # Cloudflare Tunnel
│   └── argocd.yaml.gotmpl
├── docs/                          # Documentation
├── README.md                       # This file
└── .gitignore
```

## Best Practices

- **Environment-specific secrets**: Use different tokens/credentials per environment
- **Helm values**: Override via environment variables, not git
- **GitOps workflow**: Use ArgoCD for automatic deployments
- **Multi-team**: Each team can deploy independently with their config
- **IaC**: Version all infrastructure changes in git

## License

MIT

## Support

For issues and questions, use GitHub issues or contact: draju1980
