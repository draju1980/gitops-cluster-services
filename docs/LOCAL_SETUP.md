# Local Kubernetes Setup Guide

This guide explains how to deploy cluster-services to local Kubernetes clusters with proper storage configuration.

## Supported Local Kubernetes Clusters

- **Docker Desktop**: Built-in Kubernetes support (macOS, Windows, Linux)
- **kind (Kubernetes in Docker)**: Lightweight containerized Kubernetes for testing
- **minikube**: Local Kubernetes development cluster
- **k3s**: Lightweight Kubernetes distribution

## Prerequisites

```bash
# Install required tools
brew install kubectl helm helmfile  # macOS
# or appropriate package manager for your OS

# Verify installation
kubectl version --client
helm version
helmfile version
```

## Quick Start - Local Setup

### 1. Create a Local Kubernetes Cluster

**Using Docker Desktop (macOS/Windows):**
```bash
# Enable Kubernetes in Docker Desktop settings
# Settings → Kubernetes → Enable Kubernetes
# Wait for cluster to be ready
kubectl cluster-info
```

**Using kind:**
```bash
brew install kind
kind create cluster --name gitops
kubectl cluster-info --context kind-gitops
```

**Using minikube:**
```bash
brew install minikube
minikube start --driver=docker
eval $(minikube docker-env)
```

### 2. Set Required Environment Variables

```bash
# Basic cluster configuration
export CLUSTER_NAME="local"
export CLUSTER_DOMAIN="localhost"

# Storage configuration (optional - defaults to local-storage)
export PROVIDER="local"
export STORAGE_CLASS="local-storage"

# Cloudflare credentials (for local testing, use dummy values)
export CLOUDFLARE_TOKEN="dummy-token-for-local-testing"
export CLOUDFLARE_ACCOUNT_ID="dummy-account-id"

# ArgoCD admin password hash (bcrypt)
# You can generate one with: python3 -c "import crypt; print(crypt.crypt('yourpassword', crypt.METHOD_BLOWFISH))"
export ARGOCD_ADMIN_PASSWORD_HASH='$2a$10$R9h7cIPooruNMMwq.L7KqOOtV27x8BwwfHuPVnKfKWGz/BnQuZ8eC'

# Grafana Cloud credentials (optional - for observability)
export GRAFANA_CLOUD_TOKEN="local-token-for-testing"
export GRAFANA_CLOUD_PROM_URL="https://prometheus-prod-43-prod-ap-south-1.grafana.net/api/prom/push"
export GRAFANA_CLOUD_PROM_USER="123456"
export GRAFANA_CLOUD_LOKI_URL="https://logs-prod-028.grafana.net/loki/api/v1/push"
export GRAFANA_CLOUD_LOKI_USER="123456"
export GRAFANA_CLOUD_TEMPO_URL="tempo-prod-19-prod-ap-south-1.grafana.net:443"
export GRAFANA_CLOUD_TEMPO_USER="123456"
```

### 3. Deploy Cluster Services

```bash
# Preview the deployment
helmfile template | head -100

# Deploy to local cluster
helmfile sync

# Verify deployment
kubectl get all -A
kubectl get pods -n monitoring
kubectl get pods -n argo-cd
```

## Storage Class Configuration

### Available Storage Classes

The deployment creates multiple StorageClasses for different cloud providers:

| StorageClass | Provider | Type | Use Case |
|---|---|---|---|
| `local-storage` | Local/On-prem | No provisioning | Local k8s clusters (kind, minikube, docker-desktop) |
| `ebs-gp3` | AWS | EBS General Purpose SSD | AWS EKS clusters |
| `gce-pd-ssd` | Google Cloud | Persistent Disk SSD | GKE clusters |
| `azure-managed-disk` | Azure | Managed Disk Premium | AKS clusters |
| `do-block-storage` | DigitalOcean | Block Storage | DOKS clusters |

### Using Different Storage Classes

```bash
# Local cluster (default)
export PROVIDER="local"
export STORAGE_CLASS="local-storage"

# AWS EKS
export PROVIDER="aws"
export STORAGE_CLASS="ebs-gp3"

# Google Cloud GKE
export PROVIDER="gcp"
export STORAGE_CLASS="gce-pd-ssd"

# Azure AKS
export PROVIDER="azure"
export STORAGE_CLASS="azure-managed-disk"

# DigitalOcean DOKS
export PROVIDER="do"
export STORAGE_CLASS="do-block-storage"

helmfile sync
```

## Troubleshooting

### ConfigMap "alloy-config" not found

This error indicates the Alloy ConfigMap wasn't created before the pod tried to mount it.

**Solution:**
```bash
# Verify storage classes are created
kubectl get storageclass

# Check if ConfigMap exists
kubectl get configmap -n monitoring

# Check Alloy pod status
kubectl get pods -n monitoring -l app=alloy

# View pod logs
kubectl logs -n monitoring -l app=alloy
```

### Storage provisioning issues

If you see `PersistentVolumeClaim is not bound` errors:

```bash
# Check PVC status
kubectl get pvc -A

# For local storage, manually create a PersistentVolume
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: local-pv-1
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  storageClassName: local-storage
  local:
    path: /data/local-pv-1
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - <node-name>
EOF
```

### Alloy metrics not appearing in Grafana

```bash
# Check Alloy configuration
kubectl get configmap -n monitoring alloy-config -o yaml

# View Alloy logs
kubectl logs -n monitoring -l app=alloy -f

# Check if Alloy can reach Grafana Cloud
kubectl exec -it -n monitoring <pod-name> -- \
  curl -v https://prometheus-prod-43-prod-ap-south-1.grafana.net/api/prom/push
```

### ArgoCD not accessible

```bash
# Port forward to access ArgoCD
kubectl port-forward -n argo-cd svc/argo-cd-server 8080:443

# Navigate to https://localhost:8080
# Username: admin
# Password: <value-from-your-hash>

# View ArgoCD logs
kubectl logs -n argo-cd -l app.kubernetes.io/name=argocd-application-controller -f
```

## Next Steps

1. **Access ArgoCD**: Set up port forwarding and configure auto-sync for applications
2. **Enable Alloy Scraping**: Update Alloy configuration in `releases/observability.yaml.gotmpl`
3. **Configure Networking**: Set up Cloudflare Tunnel for external access
4. **Monitor**: Check Grafana Cloud dashboards for metrics collection

## Tips for Local Development

### Save environment variables in a shell script

```bash
# Create ~/.cluster-services-dev.sh
cat > ~/.cluster-services-dev.sh <<'EOF'
#!/bin/bash

export CLUSTER_NAME="local"
export CLUSTER_DOMAIN="localhost"
export PROVIDER="local"
export STORAGE_CLASS="local-storage"

export CLOUDFLARE_TOKEN="dummy-local"
export CLOUDFLARE_ACCOUNT_ID="dummy-local"

export ARGOCD_ADMIN_PASSWORD_HASH='$2a$10$R9h7cIPooruNMMwq.L7KqOOtV27x8BwwfHuPVnKfKWGz/BnQuZ8eC'

export GRAFANA_CLOUD_TOKEN="local-test"
export GRAFANA_CLOUD_PROM_URL="https://prometheus-prod-43-prod-ap-south-1.grafana.net/api/prom/push"
export GRAFANA_CLOUD_PROM_USER="123456"
export GRAFANA_CLOUD_LOKI_URL="https://logs-prod-028.grafana.net/loki/api/v1/push"
export GRAFANA_CLOUD_LOKI_USER="123456"
export GRAFANA_CLOUD_TEMPO_URL="tempo-prod-19-prod-ap-south-1.grafana.net:443"
export GRAFANA_CLOUD_TEMPO_USER="123456"
EOF

chmod +x ~/.cluster-services-dev.sh

# Use it
source ~/.cluster-services-dev.sh
helmfile sync
```

### Quick validation

```bash
# Template and check for errors
helmfile template | kubeconform -strict

# Lint YAML
helmfile template | yamllint -d "{rules: {line-length: {max: 120}}}" -

# Check manifests
helmfile diff
```

## Multi-environment Deployment

After local testing, deploy to different environments:

```bash
# Dev environment (AWS EKS)
export CLUSTER_NAME="dev"
export PROVIDER="aws"
export STORAGE_CLASS="ebs-gp3"
helmfile sync

# Staging environment (GCP GKE)
export CLUSTER_NAME="staging"
export PROVIDER="gcp"
export STORAGE_CLASS="gce-pd-ssd"
helmfile sync

# Production (Azure AKS)
export CLUSTER_NAME="prod"
export PROVIDER="azure"
export STORAGE_CLASS="azure-managed-disk"
helmfile sync
```

## References

- [kind Documentation](https://kind.sigs.k8s.io/)
- [minikube Documentation](https://minikube.sigs.k8s.io/)
- [Docker Desktop Kubernetes](https://docs.docker.com/desktop/features/kubernetes/)
- [Kubernetes StorageClasses](https://kubernetes.io/docs/concepts/storage/storage-classes/)
