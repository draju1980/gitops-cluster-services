# Grafana Cloud Migration Guide

## Overview

This document describes the refactoring from a local observability stack to **Grafana Cloud Alloy** for all metrics, logs, and traces collection.

## What Changed

### Removed Components

**Local Observability Stack (all via `releases/observability.yaml.gotmpl`):**
- ❌ `kube-prometheus-stack` (Prometheus + Grafana)
- ❌ `thanos` (long-term metrics storage)
- ❌ `loki` (log aggregation)
- ❌ `tempo` (trace collection)
- ❌ `promtail` (log shipper)

**Why?** These added operational overhead and resource usage. Grafana Cloud provides managed versions of all these components.

### Added Components

**New Observability Solution (`releases/observability.yaml.gotmpl`):**
- ✅ `grafana-alloy` - Lightweight agent that scrapes metrics and logs, sends to Grafana Cloud
- ✅ `metrics-server` - Kubernetes metrics for HPA/VPA (unchanged)
- ✅ `monitoring-secretstore` - Pulls Grafana Cloud credentials from Vault

### Architecture Before vs After

**Before (Local Stack):**
```
Kubernetes Cluster
├── Prometheus (scrapes metrics)
├── Grafana (visualizes data)
├── Loki (stores logs)
├── Tempo (stores traces)
├── Thanos (long-term metrics)
└── S3 Storage (DigitalOcean Spaces)
```

**After (Grafana Cloud):**
```
Kubernetes Cluster
└── Grafana Alloy Agent
    ├── Scrapes metrics → Grafana Cloud Prometheus
    ├── Collects logs → Grafana Cloud Loki
    └── Collects traces → Grafana Cloud Tempo
```

## Configuration Changes

### helmfile.yaml.gotmpl

**Added:** Grafana Helm repository
```yaml
- name: grafana
  url: https://grafana.github.io/helm-charts
```

### releases/observability.yaml.gotmpl

**Completely refactored** with:

1. **Metrics Server** - Unchanged, still required for Kubernetes metrics

2. **Monitoring SecretStore** - Pulls Grafana Cloud credentials from Vault
   - `username` - Grafana Cloud instance username
   - `password` - Grafana Cloud API token
   - `prometheus-url` - Prometheus remote write URL
   - `loki-url` - Loki logs push URL
   - `tempo-url` - Tempo traces endpoint (optional)

3. **Grafana Alloy Agent** - Lightweight collector with:
   - **Prometheus Scraping:** Discovers and scrapes all pods/nodes/services
   - **Log Collection:** Gathers all container logs
   - **Trace Reception:** Optional OTLP receiver for application traces
   - **Remote Write:** Sends all data to Grafana Cloud

## Required Vault Configuration

Your Vault must contain Grafana Cloud credentials at:
```
gitops/<environment>/grafana-cloud
```

With these properties:
```json
{
  "username": "YOUR_GRAFANA_CLOUD_USERNAME_OR_EMAIL",
  "password": "YOUR_GRAFANA_CLOUD_API_TOKEN",
  "prometheus-url": "https://prometheus-blocks-prod-*.grafana.net/api/prom/push",
  "loki-url": "https://logs-prod-*.grafana.net/loki/api/v1/push",
  "tempo-url": "https://tempo-blocks-prod-*.grafana.net:443"  // optional
}
```

Replace `*` with your actual Grafana Cloud region (e.g., `us-central1`).

**To add to Vault:**
```bash
vault kv put secret/gitops/dev/grafana-cloud \
  username="user@example.com" \
  password="YOUR_API_TOKEN" \
  prometheus-url="https://prometheus-blocks-prod-us-central1.grafana.net/api/prom/push" \
  loki-url="https://logs-prod-us-central1.grafana.net/loki/api/v1/push" \
  tempo-url="https://tempo-blocks-prod-us-central1.grafana.net:443"
```

## Deployment Steps

### 1. Create Grafana Cloud Account

If you don't have one, sign up at: https://grafana.com/products/cloud/

### 2. Get Your Credentials

From Grafana Cloud UI:
- Go to **Connections → Data Sources → Prometheus**
- Copy the **Username** and **API Token**
- Get the **Remote write URL** for Prometheus
- Get the **Loki push URL** from Loki data source
- Get **Tempo endpoint** (optional for traces)

### 3. Store in Vault

```bash
vault kv put secret/gitops/dev/grafana-cloud \
  username="YOUR_USERNAME" \
  password="YOUR_API_TOKEN" \
  prometheus-url="YOUR_PROM_URL" \
  loki-url="YOUR_LOKI_URL" \
  tempo-url="YOUR_TEMPO_URL"
```

### 4. Deploy

```bash
# Set required environment variables
export VAULT_ADDR="https://your-vault.example.com"
export VAULT_TOKEN="your-vault-token"
export CLUSTER_NAME="dev"
export CLUSTER_DOMAIN="example.com"
export GITHUB_TOKEN="your-github-token"
export CLOUDFLARE_TOKEN="your-cf-token"
export CLOUDFLARE_ACCOUNT_ID="your-cf-account"
export ARGOCD_ADMIN_PASSWORD_HASH="your-argocd-hash"

# Deploy with helmfile
helmfile sync
```

### 5. Verify

```bash
# Check Alloy pods are running
kubectl get pods -n monitoring -l app=alloy

# View Alloy logs
kubectl logs -n monitoring -l app=alloy -f

# Check the Grafana Cloud UI for incoming metrics/logs
```

## Benefits

✅ **Reduced Operational Overhead**
- No local Prometheus/Grafana/Loki/Tempo to manage
- Grafana Cloud handles all updates and maintenance

✅ **Reduced Resource Usage**
- Alloy is lightweight (~200m CPU, ~256Mi memory)
- vs. full stack: ~2-4 CPU cores, ~4-8Gi memory

✅ **Simplified Architecture**
- Single agent instead of 5+ components
- Easier to understand and troubleshoot

✅ **Cloud-Native Benefits**
- Grafana Cloud provides high availability
- Automatic scaling and backups
- Built-in alerting and dashboards

✅ **Cost Efficiency**
- Pay only for what you use
- No S3 storage costs for Thanos/Loki/Tempo

## Rollback Plan

If you need to revert to the local stack:

1. Revert this commit
2. Restore `releases/observability.yaml.gotmpl` from git history
3. Ensure your S3 buckets still have data for Thanos/Loki/Tempo
4. Re-deploy with helmfile

## Monitoring the Alloy Agent

### Key Metrics from Alloy

Alloy exports its own metrics on port 12345:
```bash
kubectl port-forward -n monitoring svc/grafana-alloy 12345:12345
# Access at http://localhost:12345/metrics
```

Key metrics:
- `prometheus_sd_discovered_targets` - Number of targets discovered
- `prometheus_remote_write_samples_sent_total` - Samples sent to Grafana Cloud
- `loki_write_sent_entries_total` - Log entries sent to Grafana Cloud

### Logging

Check Alloy logs for any scraping errors:
```bash
kubectl logs -n monitoring -l app=alloy -f
```

## Troubleshooting

### No metrics appearing in Grafana Cloud

1. **Check Alloy pods are running:**
   ```bash
   kubectl get pods -n monitoring -l app=alloy
   ```

2. **Check Grafana Cloud credentials:**
   ```bash
   kubectl get secret grafana-cloud-credentials -n monitoring -o yaml
   ```

3. **Check Alloy logs for errors:**
   ```bash
   kubectl logs -n monitoring -l app=alloy | grep -i error
   ```

4. **Verify network connectivity:**
   ```bash
   kubectl exec -it -n monitoring <alloy-pod> -- \
     curl -v https://prometheus-blocks-prod-*.grafana.net/api/prom/push
   ```

### High cardinality metrics

The Alloy configuration includes a metric relabel rule to drop high-cardinality kubelet metrics:
```yaml
metric_relabel "drop_high_cardinality" {
  action = "drop"
  source_labels = ["__name__"]
  regex = "kubelet_volume_stats_used_bytes|kubelet_volume_stats_capacity_bytes"
}
```

Adjust the regex if you see cardinality warnings in Grafana Cloud.

## Next Steps

1. ✅ Update Vault with Grafana Cloud credentials
2. ✅ Deploy the changes with `helmfile sync`
3. ✅ Verify metrics/logs appear in Grafana Cloud
4. ✅ Update any local dashboards/alerts to use Grafana Cloud
5. ✅ Archive or delete the old `bootstrap/` and local observability configs
