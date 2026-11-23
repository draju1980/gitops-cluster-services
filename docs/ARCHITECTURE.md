# GitOps Platform Services Architecture

## Overview

This repository manages Kubernetes cluster-wide platform services using a GitOps approach. It implements the **App of Apps pattern** with ArgoCD and **Helmfile** as the deployment orchestrator.

## Technology Stack

### GitOps & Orchestration
- **ArgoCD**: Declarative GitOps management
- **Helmfile**: Helm release orchestration and environment management
- **App of Apps Pattern**: Hierarchical application management

### Secrets & Configuration
- **HashiCorp Vault Cloud**: Centralized secrets management
- **External Secrets Operator (ESO)**: Kubernetes-native secret synchronization
- **1Password**: Secret backend integration

### Networking
- **Cloudflare Tunnel**: Secure cluster access without public IPs
- **Cloudflare DNS**: External DNS management
- **Cert Manager**: TLS certificate lifecycle management
- **Ingress NGINX**: Ingress controller

### Observability
- **Prometheus**: Metrics collection and storage
- **Grafana Cloud**: Managed visualization and alerting
- **Grafana Alloy**: Telemetry collector (logs, metrics, traces)
- **Loki**: Log aggregation
- **Tempo**: Distributed tracing
- **Thanos**: Long-term metric storage and querying

### Security
- **Kyverno**: Kubernetes policy engine (Pod Security, Network Policies)
- **Falco**: Runtime security and threat detection
- **Trivy Operator**: Container image and configuration scanning

## Architecture Decision: ArgoCD + Helmfile Integration

### The Problem
ArgoCD cannot natively render Helmfile syntax. Without special handling, two approaches create conflicts:
1. CI renders Helmfile → commits manifests → ArgoCD syncs (loses Helmfile benefits)
2. ArgoCD and CI both try to apply changes (bidirectional sync conflicts)

### The Solution: Config Management Plugin

We use **ArgoCD Config Management Plugin (CMP)** with the `helmfile` plugin sidecar:

```
User commits to git
    ↓
ArgoCD detects change
    ↓
CMP sidecar: helmfile -e <env> template
    ↓
Generated manifests
    ↓
ArgoCD applies with auto-sync, prune, self-heal
```

**Benefits:**
- ✅ Single source of truth (Helmfile)
- ✅ Environment-specific values via `helmfile.d/`
- ✅ Full ArgoCD features (auto-sync, prune, self-heal, notifications)
- ✅ No CI/CD conflicts

**Implementation:**
- ArgoCD repoServer includes `travisghansen/argo-cd-helmfile` CMP sidecar
- Each Application references this plugin
- Plugin env vars: `HELMFILE_EXPERIMENTAL=true`, `HELMFILE_CACHE_CLEANUP=true`

## Repository Structure

```
gitops-cluster-services/
├── bootstrap/                 # Bootstrap ArgoCD and initial setup
│   └── argocd/
│       ├── namespace.yaml
│       ├── helm-values.yaml
│       └── install.sh
│
├── argocd/                    # ArgoCD configuration
│   ├── projects/              # AppProjects with RBAC
│   │   ├── platform.yaml
│   │   ├── security.yaml
│   │   ├── observability.yaml
│   │   └── networking.yaml
│   └── applications/          # Application manifests
│       └── app-of-apps.yaml   # Root application
│
├── cloudflare/                # Cloudflare tunnel & DNS
│   ├── tunnel.yaml
│   └── external-dns.yaml
│
├── vault/                     # Vault integration
│   ├── auth.yaml              # Kubernetes auth
│   ├── secretstore.yaml       # ClusterSecretStore
│   └── externalsecret.yaml    # Example ExternalSecret
│
├── observability/             # Monitoring & logging
│   ├── grafana-alloy/
│   ├── dashboards/
│   ├── alerts/
│   └── otel/
│
├── security/                  # Security policies
│   ├── kyverno/
│   │   ├── policies/
│   │   └── exceptions.yaml
│   ├── falco/
│   ├── trivy/
│   └── network-policies/
│
├── ingress/                   # Ingress & TLS
│   ├── ingress-nginx.yaml
│   └── cert-manager.yaml
│
├── helmfile.yaml.gotmpl       # Root helmfile
├── helmfile.d/                # Environment-specific values
│   ├── dev.yaml
│   ├── staging.yaml
│   └── prod.yaml
│
├── releases/                  # Helmfile releases
│   ├── namespaces.yaml.gotmpl
│   ├── argocd.yaml.gotmpl
│   ├── networking.yaml.gotmpl
│   ├── observability.yaml.gotmpl
│   ├── security.yaml.gotmpl
│   ├── vault.yaml.gotmpl
│   └── ingress.yaml.gotmpl
│
└── docs/
    ├── ARCHITECTURE.md
    ├── BOOTSTRAP.md
    ├── OPERATING_MODEL.md
    └── CONVENTIONS.md
```

## Namespaces and ArgoCD Projects

| Component | Namespace | Project | Charts | Sync Wave |
|-----------|-----------|---------|--------|-----------|
| Namespaces | - | default | raw/generic | 0 |
| ArgoCD | argocd | platform | argoproj/argo-cd | 0 |
| Cert Manager CRDs | cert-manager | security | jetstack/cert-manager-crds | 1 |
| Cert Manager | cert-manager | security | jetstack/cert-manager | 2 |
| External Secrets CRDs | external-secrets | vault | external-secrets/external-secrets | 1 |
| External Secrets | external-secrets | vault | external-secrets/external-secrets | 2 |
| Vault Integration | external-secrets | vault | raw/generic | 3 |
| Kyverno CRDs | kyverno | security | kyverno/kyverno-crds | 1 |
| Kyverno | kyverno | security | kyverno/kyverno | 2 |
| Kyverno Policies | kyverno | security | raw/generic | 3 |
| Falco | falco | security | falcosecurity/falco | 3 |
| Trivy | trivy-system | security | aquasecurity/trivy-operator | 3 |
| Prometheus Stack | monitoring | observability | prometheus-community/kube-prometheus-stack | 3 |
| Loki | monitoring | observability | grafana/loki | 3 |
| Tempo | monitoring | observability | grafana/tempo-distributed | 3 |
| Grafana Alloy | monitoring | observability | grafana/k8s-monitoring | 4 |
| Thanos | monitoring | observability | bitnami/thanos | 3 |
| Ingress NGINX | ingress-nginx | networking | ingress-nginx/ingress-nginx | 3 |
| Cloudflare Tunnel | cloudflare | networking | strrl.dev/cloudflare-tunnel-ingress-controller | 3 |
| External DNS | external-dns | networking | bitnami/external-dns | 3 |
| Metrics Server | kube-system | platform | metrics-server/metrics-server | 0 |

**Sync Wave Strategy:**
- **Wave 0**: Core infrastructure (namespaces, metrics-server)
- **Wave 1**: CRD-only releases (cert-manager-crds, external-secrets-crds, kyverno-crds)
- **Wave 2**: Operators that use CRDs from Wave 1
- **Wave 3**: Applications and policy resources
- **Wave 4**: Collectors and final observability components

## Production-Ready Features

### Sync Configuration
- **Auto Sync**: Enabled for platform services, manual for critical infrastructure
- **Self Heal**: Enabled - ArgoCD corrects drift automatically
- **Prune**: Enabled - removes resources deleted from git
- **ServerSideApply**: Enabled for Kyverno (large CRDs)
- **SkipDryRunOnMissingResource**: Enabled for policy resources (depends on CRDs from earlier waves)

### Security Policies
- Privileged namespaces: `kube-system`, `argocd`, `cert-manager`, `external-secrets`, `kyverno`, `falco`, `trivy-system`
- PSS enforce labels: Applied to privileged namespaces only
- Default-deny NetworkPolicies: Allow API server webhooks for mutation/validation
- Secret zero: No real tokens in git; only placeholders for out-of-band setup

### Kyverno
- **Audit Mode** in dev (logs violations)
- **Enforce Mode** in prod (blocks violations)
- **Exclusions**: kube-system, argocd, kyverno namespaces excluded
- **Mutation**: Image registry rewrite, image pull policy enforcement
- **Validation**: Pod security standards, resource limits, network policies

### Vault Integration
- **Kubernetes Auth**: Cluster API TokenReview (supports private clusters via JWT)
- **Namespace-level Secrets**: Each app namespace has its own SecretStore
- **Rotation**: ESO syncs secrets continuously
- **Zero Trust**: No secrets in git; only SecretStore references

### Networking
- **Cloudflare Tunnel**: Exposes cluster without public ingress IPs
- **External DNS**: Cloudflare manages DNS records automatically
- **Cert Manager**: Automated TLS cert management via Let's Encrypt
- **Network Policies**: Explicit allow-lists; API server webhooks whitelisted

### Observability
- **Metrics**: Prometheus scrapes Kube API, kubelets, applications
- **Logs**: Promtail → Loki, forward to Grafana Cloud
- **Traces**: Prometheus OTLP receiver, Tempo backend
- **Long-term Storage**: Thanos queries Prometheus + object storage
- **Alloy**: Metrics, logs, traces → Grafana Cloud

## Deployment Workflow

```
Developer commits to gitops-cluster-services
    ↓
GitHub webhook → ArgoCD detects change
    ↓
ArgoCD pulls latest commit
    ↓
CMP plugin runs: helmfile -e dev|staging|prod template
    ↓
Generated YAML passed to kubectl apply (server-side)
    ↓
Auto-sync: ArgoCD applies changes immediately
    ↓
Self-heal: ArgoCD corrects any drift
    ↓
Prune: Removed resources deleted from git
    ↓
Notifications: Slack alerts on sync status
```

## Bootstrap Process

See [BOOTSTRAP.md](./BOOTSTRAP.md) for detailed bootstrap steps.

## Operating Model

See [OPERATING_MODEL.md](./OPERATING_MODEL.md) for day-2 operations, troubleshooting, and maintenance.

## Secrets Management

### Secret Zero
At bootstrap, create manually in cluster:
- 1Password API token (for Helmfile secret injection)
- GitHub token (for ArgoCD repo access)
- Vault Kubernetes auth JWT

After bootstrap, all secrets managed by:
- 1Password (Helmfile {{ fetchSecretValue }})
- Vault (ExternalSecret resources)

### ExternalSecret Pattern
```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: app-secrets
  namespace: app-namespace
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: app-secrets
    creationPolicy: Owner
  data:
    - secretKey: api-key
      remoteRef:
        key: secret/data/app/api-key
```

## Validation & Testing

All changes must pass:
1. **yamllint**: YAML syntax validation
2. **helmfile -e {env} template**: Environment-specific rendering
3. **kubeconform**: Kubernetes schema validation
4. **Kyverno policy checks**: Dry-run validation (Audit mode in dev)

CI/CD pipeline validates on every commit; manual validation before production sync.

## Troubleshooting

### ArgoCD Application Stuck "Progressing"
- Check CMP plugin logs: `kubectl logs -n argocd deployment/argocd-repo-server -c helmfile-cmp`
- Verify helmfile syntax: `helmfile -e <env> template --show-secrets`
- Check image pull secrets in argo-cd namespace

### Vault Auth Failing
- Verify JWT issuer: `kubectl -n external-secrets get clusterSecretStore -o yaml`
- Check Vault Kubernetes auth policy
- Ensure cluster API is reachable from Vault (or configure JWT issuer)

### Kyverno Blocking Deployments
- Check policy audit logs: `kubectl get policyreport -A`
- Verify exemptions in policies/exceptions.yaml
- Test in Audit mode first before Enforce

## References

- [ArgoCD Docs](https://argo-cd.readthedocs.io/)
- [Helmfile Docs](https://helmfile.readthedocs.io/)
- [Kyverno Docs](https://kyverno.io/docs/)
- [External Secrets Operator](https://external-secrets.io/)
- [Cert Manager](https://cert-manager.io/)
