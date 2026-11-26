# Cluster Services Architecture

## Design Philosophy

**Minimal**: Only 4 essential releases; no forced dependencies  
**Modular**: Deploy once, use everywhere with environment variables  
**Cloud-Native**: Leverage managed services (Grafana Cloud) instead of local deployments  
**Secure**: Zero secrets in git; all via environment variables  
**Operational**: Low resource usage; easy to maintain and troubleshoot  

## System Overview

```
Kubernetes Cluster
│
├─ Namespaces
│  ├─ argo-cd       (GitOps orchestration)
│  ├─ monitoring    (Observability collection)
│  └─ cloudflare    (Secure ingress)
│
├─ Observability
│  └─ Grafana Alloy Agent
│     ├─ Metrics  → Grafana Cloud Prometheus
│     ├─ Logs     → Grafana Cloud Loki
│     └─ Traces   → Grafana Cloud Tempo
│
├─ Networking
│  └─ Cloudflare Tunnel
│     └─ Ingress through Cloudflare
│
└─ GitOps
   └─ ArgoCD
      └─ Declarative management via git
```

## 4 Essential Helm Releases

### 1. Namespaces
**Chart**: Custom (via git)  
**Purpose**: Creates monitoring, argo-cd, cloudflare namespaces  
**Resources**: 3 Namespace objects  
**Dependency**: First (required by others)

### 2. Observability  
**Chart**: grafana/alloy  
**Purpose**: Collects metrics, logs, and traces from cluster  
**Components**:
- Grafana Alloy Agent (DaemonSet-like)
- Kubernetes Secret for Grafana Cloud credentials
- ServiceAccount with minimal RBAC

**Capabilities**:
- Discovers and scrapes all Kubernetes metrics
- Collects container logs from all pods
- Receives OTLP traces on ports 4317 (gRPC) and 4318 (HTTP)
- Sends to Grafana Cloud (fully managed, zero local storage)

**Resources**:
- CPU: 200m request, 500m limit
- Memory: 256Mi request, 512Mi memory limit
- Runs with system-cluster-critical priority

### 3. Networking
**Chart**: strrl.dev/cloudflare-tunnel-ingress-controller  
**Purpose**: Secure ingress without public IPs  
**Components**:
- Cloudflare Tunnel Controller
- Cloudflared daemon (configurable replicas)
- ServiceMonitor for metrics

**How it works**:
- Establishes outbound-only tunnel to Cloudflare
- Routes all ingress through Cloudflare
- No TLS management needed
- Configurable replicas for HA (dev: 1, staging: 2, prod: 3)

### 4. ArgoCD
**Chart**: argoproj/argo-cd  
**Purpose**: GitOps continuous deployment  
**Components**:
- ArgoCD Server (API + UI)
- ArgoCD RepoServer with Helmfile CMP plugin
- ArgoCD Application Controller
- ArgoCD ServiceMonitor

**Features**:
- Monitors GitHub repository
- Renders Helmfile templates automatically
- Auto-syncs on git changes
- Self-heals if manual changes made
- Prunes deleted resources

## Helm Repositories

**3 repositories total** (minimal attack surface):

```yaml
repositories:
  - name: argoproj
    url: https://argoproj.github.io/argo-helm
    
  - name: grafana
    url: https://grafana.github.io/helm-charts
    
  - name: strrl.dev
    url: https://helm.strrl.dev
```

## Environment Variable Strategy

**Key Principle**: cluster-services is a reusable module

Same code deploys to:
- Different organizations (Team A vs Team B)
- Different clusters (dev, staging, prod)
- Different Grafana Cloud instances (US region vs EU region)
- Different security postures (1 replica vs 3 replicas HA)

**Solution**: All configuration via environment variables

```bash
# Team A (Grafana instance in US)
export GRAFANA_CLOUD_PROM_URL="https://prometheus-prod-11-prod-us-central1.grafana.net/api/prom/push"
export GRAFANA_CLOUD_PROM_USER="123456"
helmfile sync

# Team B (Grafana instance in EU)
export GRAFANA_CLOUD_PROM_URL="https://prometheus-prod-22-prod-eu-west-1.grafana.net/api/prom/push"
export GRAFANA_CLOUD_PROM_USER="654321"
helmfile sync
```

## Data Flows

### Metrics Collection

```
Kubernetes Cluster Metrics
  ↓
Alloy discovers: pods, nodes, services
  ↓
Alloy scrapes Prometheus format
  ↓
Metric relabeling (drop high-cardinality)
  ↓
Add cluster=<CLUSTER_NAME> label
  ↓
Prometheus remote write to Grafana Cloud
  ↓
Visualize in Grafana Cloud dashboards
```

### Log Collection

```
Container stdout/stderr
  ↓
Alloy reads from /var/log/containers/
  ↓
Label processing (drop noisy Kubernetes labels)
  ↓
Loki API push to Grafana Cloud
  ↓
Search/explore in Grafana Cloud
```

### Trace Collection

```
Application (OTLP client)
  ↓
Sends to Alloy port 4317 (gRPC) or 4318 (HTTP)
  ↓
Alloy OTLP receiver
  ↓
OTLP exporter with basic auth
  ↓
Tempo API endpoint in Grafana Cloud
  ↓
Trace visualization in Grafana Cloud
```

### GitOps Deployment

```
Developer pushes to GitHub
  ↓
GitHub webhook → ArgoCD
  ↓
ArgoCD pulls repository
  ↓
CMP plugin: helmfile template --environment <env>
  ↓
Helmfile renders manifests with environment values
  ↓
ArgoCD compares with current cluster state
  ↓
If drift detected → auto-sync
  ↓
kubectl apply generated manifests
  ↓
Cluster updated
```

## Configuration

### helmfile.yaml.gotmpl Structure

```yaml
repositories:
  - argoproj, grafana, strrl.dev

environments:
  default:
    values:
      clusterName: (from env)
      domain: (from env)
      argocd:
        adminpasswordhashed: (from env)
      github:
        accesstoken: (from env)
      cloudflare:
        apitoken: (from env)
        accountid: (from env)
      ingressController:
        replicaCount: 1
        cloudflared:
          replicaCount: (from env, default 1)
      grafanaCloud:
        token: (from env)
        prometheus:
          url: (from env)
          username: (from env)
        loki:
          url: (from env)
          username: (from env)
        tempo:
          url: (from env)
          username: (from env)

helmfiles:
  - releases/namespaces.yaml.gotmpl
  - releases/observability.yaml.gotmpl
  - releases/networking.yaml.gotmpl
  - releases/argocd.yaml.gotmpl
```

## Comparison: Simplified vs Complex

| Aspect | Complex Stack | Simplified Stack |
|--------|---------------|------------------|
| **Local Prometheus** | Yes (StatefulSet) | No (Grafana Cloud) |
| **Local Grafana** | Yes (Deployment) | No (Grafana Cloud UI) |
| **Local Loki** | Yes (DaemonSet+StatefulSet) | No (Grafana Cloud) |
| **Local Tempo** | Yes (StatefulSet) | No (Grafana Cloud) |
| **Thanos** | Yes (sidecar+query) | No (Grafana Cloud) |
| **Local Storage** | 50-100Gi PVCs | None |
| **Local CPU** | ~2-4 cores | ~500m |
| **Local Memory** | ~4-8Gi | ~640Mi |
| **Charts/Repos** | 10+ | 3 |
| **Configuration** | Complex, environment-specific | Simple, via env vars |
| **Operational Load** | High (upgrades, maintenance) | Low (managed service) |
| **Cost (Local)** | High (resources + storage) | Low |
| **Cost (Observability)** | Storage costs | Consumption-based |
| **Multi-cluster Consistency** | Difficult | Easy (same code) |
| **Disaster Recovery** | Cluster loss = data loss | Cluster loss = data persists in Grafana |

## Security Model

### Secret Management

**Before**: Environment variables for all secrets (not ideal)  
**Now**: Environment variables for flexibility (users can get from Vault)

Each organization can wrap this:
```bash
# Example: Team gets secrets from their Vault
export GITHUB_TOKEN="$(vault kv get -field=token secret/github)"
export GRAFANA_CLOUD_TOKEN="$(vault kv get -field=token secret/grafana-cloud)"
helmfile sync
```

### Network Security

- **Cloudflare Tunnel**: Cluster has no public IP; all external traffic through Cloudflare
- **Internal Communication**: Pod-to-pod, pod-to-service (user-configured network policies)
- **TLS**: Cloudflare terminates TLS; cluster communications encrypted by Kubernetes

### RBAC

- **Alloy**: Minimal service account (read pods, nodes, services, metrics)
- **ArgoCD**: User-configured (can deploy anything or restricted)
- **Cloudflare**: API-token only; no cluster-side access

## Upgrade Path

### Chart Version Upgrades

1. Update version in `releases/*.yaml.gotmpl`
2. Run `helmfile diff` to preview
3. Push to git
4. ArgoCD auto-syncs (if auto-sync enabled)

### Environment Variable Changes

1. Update environment variable
2. Run `helmfile sync`
3. Changes take effect immediately

### Zero-Downtime Deployment

Most upgrades are zero-downtime because:
- Alloy: Can tolerate temporary collection gaps
- Cloudflare: Multiple replicas available
- ArgoCD: Stateless (can redeploy anytime)

## Resource Efficiency

### Local Resource Usage

- **Alloy**: ~200m CPU, ~256Mi memory
- **Cloudflare Tunnel**: ~100m CPU, ~128Mi memory  
- **ArgoCD**: ~300m CPU, ~512Mi memory
- **Total**: ~600m CPU, ~896Mi memory (< 1 node on typical clusters)

### Cloud Resource Usage (Grafana Cloud)

- **Metrics**: Charged per millions of samples
- **Logs**: Charged per GB ingested
- **Traces**: Charged per million spans
- No local storage = no PVC costs

## Disaster Recovery

### Cluster Destroyed Scenario

```
Cluster gone
  ↓
1. Create new Kubernetes cluster
2. Set environment variables
3. helmfile sync
  ↓
All metrics/logs/traces continue in Grafana Cloud
Historical data accessible immediately
Cluster rebuilt in minutes
```

### Configuration/Git Lost Scenario

```
Git repo deleted
  ↓
1. Clone from GitHub backup
2. Set environment variables
3. helmfile sync
  ↓
Cluster services redeployed
Full history in git
```

## Monitoring the Deployment

### Health Check

```bash
# Check all pods
kubectl get pods -A

# Check releases
helm list -A

# Check ArgoCD applications
kubectl get application -n argo-cd

# Check Alloy logs
kubectl logs -n monitoring -l app=alloy -f

# Check metrics in Grafana Cloud
curl -u username:password \
  https://prometheus-prod-43-prod-ap-south-1.grafana.net/api/prom/api/v1/query?query=up
```

### Troubleshooting

**Alloy not collecting**: Check pod logs, verify network to Grafana Cloud  
**ArgoCD not syncing**: Check CMP plugin logs, verify git access  
**Cloudflare not routing**: Check tunnel logs, verify DNS in Cloudflare dashboard  

## Future Enhancements

Possible additions without breaking simplicity:

- **Cert-Manager**: For automatic TLS (if needed with Cloudflare)
- **Kyverno**: Policy engine (optional security hardening)
- **Trivy**: Container scanning (optional supply chain security)
- **Falco**: Runtime security (optional threat detection)

## References

- [Grafana Alloy Docs](https://grafana.com/docs/alloy/latest/)
- [Grafana Cloud Docs](https://grafana.com/docs/grafana-cloud/)
- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)
- [ArgoCD Docs](https://argo-cd.readthedocs.io/)
- [Helmfile Docs](https://helmfile.readthedocs.io/)
