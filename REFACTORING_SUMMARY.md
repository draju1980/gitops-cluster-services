# Cluster Services Refactoring Summary

## Project Structure (Simplified)

```
cluster-services/
├── helmfile.yaml.gotmpl           # Root Helmfile with environment config
├── releases/
│   ├── namespaces.yaml.gotmpl     # Kubernetes namespaces
│   ├── vault.yaml.gotmpl           # External Secrets & Vault integration
│   ├── ingress.yaml.gotmpl         # Ingress config (empty - using Cloudflare Tunnel)
│   ├── networking.yaml.gotmpl      # Cloudflare Tunnel controller
│   ├── argocd.yaml.gotmpl          # ArgoCD deployment
│   └── observability.yaml.gotmpl   # ✨ REFACTORED: Grafana Cloud Alloy only
├── argocd/                         # ArgoCD configuration
│   ├── applications/               # Application definitions
│   └── projects/                   # ArgoCD projects
├── vault/                          # Vault configuration examples
├── docs/
│   ├── GRAFANA_CLOUD_MIGRATION.md  # ✨ NEW: Migration guide
│   └── ...other docs
└── bootstrap/                      # Bootstrap scripts (optional)
```

## Key Changes

### ✅ What's New

| Component | Purpose | Status |
|-----------|---------|--------|
| **Grafana Alloy Agent** | Lightweight metrics/logs/traces collector | ✨ NEW |
| **Grafana Cloud Integration** | Managed observability via Grafana Cloud | ✨ NEW |
| **Vault ExternalSecret** | Pull Grafana Cloud credentials from Vault | ✨ NEW |

### ❌ What Was Removed

| Component | Reason | Replacement |
|-----------|--------|-------------|
| **Prometheus** | Local instance unnecessary | Grafana Cloud Prometheus |
| **Grafana** | Local instance unnecessary | Grafana Cloud UI |
| **Thanos** | Long-term storage in S3 | Grafana Cloud Storage |
| **Loki** | Local log aggregation | Grafana Cloud Loki |
| **Tempo** | Local trace storage | Grafana Cloud Tempo |
| **Promtail** | Alloy handles log collection | Built into Alloy |

### 📝 What Changed

| File | Change | Impact |
|------|--------|--------|
| `helmfile.yaml.gotmpl` | Added Grafana Helm repo | Needed for Alloy chart |
| `releases/observability.yaml.gotmpl` | Complete rewrite | Now just Alloy + metrics-server |

## Deployment Requirements

### Environment Variables (unchanged)
```bash
CLUSTER_NAME              # e.g., "dev", "prod"
CLUSTER_DOMAIN           # e.g., "example.com"
VAULT_ADDR              # e.g., "https://vault.example.com"
VAULT_TOKEN             # Vault authentication token
GITHUB_TOKEN            # GitHub personal access token
CLOUDFLARE_TOKEN        # Cloudflare API token
CLOUDFLARE_ACCOUNT_ID   # Cloudflare account ID
ARGOCD_ADMIN_PASSWORD_HASH  # bcrypt hash of ArgoCD password
```

### Vault Configuration (NEW)
Store Grafana Cloud credentials in Vault:
```
Path: secret/gitops/<environment>/grafana-cloud

Fields:
  username        → Grafana Cloud username/email
  password        → Grafana Cloud API token
  prometheus-url  → Prometheus remote write endpoint
  loki-url        → Loki logs push endpoint
  tempo-url       → Tempo traces endpoint (optional)
```

## Resource Impact

### Before (Local Stack)
- **CPU Requests:** ~1200m (Prometheus 500m + Thanos 500m + others)
- **Memory Requests:** ~3Gi (Prometheus 2Gi + Loki 1Gi + others)
- **Storage:** 50-100Gi (Thanos + Loki persistence)
- **Cost:** High operational overhead

### After (Grafana Cloud Alloy)
- **CPU Requests:** ~200m (Alloy only)
- **Memory Requests:** ~256Mi (Alloy only)
- **Storage:** 0Gi (all in Grafana Cloud)
- **Cost:** Only Grafana Cloud usage + minimal local agent

## Migration Checklist

- [ ] Create Grafana Cloud account
- [ ] Get Grafana Cloud credentials (username, API token, URLs)
- [ ] Store credentials in Vault at `secret/gitops/<env>/grafana-cloud`
- [ ] Review `docs/GRAFANA_CLOUD_MIGRATION.md`
- [ ] Deploy with `helmfile sync`
- [ ] Verify metrics/logs in Grafana Cloud UI
- [ ] Update dashboards/alerts to use Grafana Cloud
- [ ] Archive or delete bootstrap/ directory (optional)

## Documentation

📖 **See `docs/GRAFANA_CLOUD_MIGRATION.md` for:**
- Detailed setup instructions
- Vault configuration steps
- Troubleshooting guide
- Rollback procedure

## Questions & Support

For issues with:
- **Grafana Cloud:** See https://grafana.com/docs/grafana-cloud/
- **Alloy:** See https://grafana.com/docs/alloy/latest/
- **Deployment:** Check logs with `kubectl logs -n monitoring -l app=alloy`
