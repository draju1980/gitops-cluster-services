# Operating Model - Day 2 Operations

This document covers how to operate gitops-cluster-services after initial bootstrap.

## Prerequisites

- Cluster already bootstrapped with ArgoCD (see BOOTSTRAP.md)
- kubectl configured to access cluster
- Vault unsealed and operational
- Helmfile and helm installed locally

## Daily Operations

### 1. Monitoring Deployment Status

Check ArgoCD application sync status:

```bash
# Watch all applications
kubectl -n argocd get applications -w

# Detailed app status
kubectl -n argocd describe app gitops-cluster-services-root

# Check specific namespace
kubectl -n monitoring get all
```

### 2. Viewing Logs

**ArgoCD sync logs:**
```bash
kubectl -n argocd logs -f deployment/argocd-repo-server -c helmfile-cmp
```

**Vault logs:**
```bash
kubectl -n vault logs -f statefulset/vault
```

**Kyverno policy audit:**
```bash
kubectl -n kyverno logs -f deployment/kyverno
kubectl get clusterpolicyreport -A
```

**Falco runtime security:**
```bash
kubectl -n falco logs -f daemonset/falco
```

**Prometheus metrics:**
```bash
kubectl -n monitoring port-forward svc/prometheus-operated 9090:9090
# Open http://localhost:9090 in browser
```

**Grafana dashboards:**
```bash
kubectl -n monitoring port-forward svc/prometheus-kube-prometheus-grafana 3000:80
# Open http://localhost:3000 in browser
```

### 3. Managing Vault

#### Unsealing Vault

If Vault pod restarts, it will be sealed. You must unseal it manually.

**Option 1: Using Raft auto-unseal (Recommended for HA)**
```bash
# The Raft cluster automatically unseals secondary nodes
# Only the leader needs manual unseal if all replicas restart

kubectl -n vault exec -it vault-0 -- vault status

# If sealed, unseal with your root token:
kubectl -n vault exec -it vault-0 -- vault operator unseal
# Enter your unseal key when prompted
```

**Option 2: Using your unseal key**
```bash
kubectl -n vault exec -it vault-0 -- vault operator unseal
# Repeat with different unseal keys until unseal progress reaches 100%
```

#### Accessing Vault UI

```bash
kubectl -n vault port-forward svc/vault 8200:8200
# Open http://localhost:8200 in browser
```

#### Creating Vault Secrets

For your applications:

```bash
# Login to Vault (if using root token):
kubectl -n vault exec -it vault-0 -- vault login <root-token>

# Create application secrets
vault kv put secret/myapp/database \
  username=dbuser \
  password=mysecretpassword

# Create API keys
vault kv put secret/myapp/api \
  key1=value1 \
  key2=value2

# List secrets
vault kv list secret/myapp/

# Read a specific secret
vault kv get secret/myapp/database
```

#### Vault Policy Management

Create policies for different applications/namespaces:

```bash
# Create a policy for app1
vault policy write app1 - <<EOF
path "secret/data/app1/*" {
  capabilities = ["read", "list"]
}
EOF

# Create Kubernetes auth role for the app
vault write auth/kubernetes/role/app1-sa \
  bound_service_account_names=app1 \
  bound_service_account_namespaces=app1 \
  policies=app1 \
  ttl=24h
```

### 4. Managing Secrets with External Secrets Operator

#### Creating an ExternalSecret

See `vault/externalsecret-example.yaml` for examples.

Example:
```bash
kubectl apply -f - <<'EOF'
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-secrets
  namespace: default
spec:
  refreshInterval: 15m
  secretStoreRef:
    name: vault
    kind: ClusterSecretStore
  target:
    name: app-secrets
    creationPolicy: Owner
  data:
    - secretKey: api-key
      remoteRef:
        key: myapp/secrets
        property: api-key
EOF
```

#### Verifying Secret Sync

```bash
# Check ExternalSecret status
kubectl -n default describe externalsecret app-secrets

# View the synced Kubernetes Secret
kubectl -n default get secret app-secrets -o yaml
```

#### Triggering Manual Refresh

```bash
# Delete the secret to force refresh
kubectl delete secret app-secrets -n default
# ESO will recreate it within 15 seconds
```

### 5. Managing Policies with Kyverno

#### Checking Policy Status

```bash
# View all policies
kubectl get clusterpolicies

# Check policy violations (audit mode)
kubectl get clusterpolicyreports -A

# See details of violations
kubectl describe clusterpolicyreport -A
```

#### Toggling Audit vs Enforce Mode

In `helmfile.d/{env}.yaml`:

```yaml
kyverno:
  validationFailureAction: "audit"   # Log violations only (dev/staging)
  # OR
  validationFailureAction: "enforce"  # Block violations (prod)
```

Then sync:
```bash
helmfile -e prod apply
```

#### Exempting Resources from Policies

Create policy exceptions:

```bash
kubectl apply -f - <<'EOF'
apiVersion: kyverno.io/v1
kind: ClusterPolicyException
metadata:
  name: exempt-kube-system
spec:
  exceptions:
    - ruleIndex: 0
      ruleType: validate
  match:
    resources:
      namespaceSelector:
        matchLabels:
          pod-security.kubernetes.io/enforce: privileged
  policies:
    - restrict-privileged-containers
EOF
```

### 6. Monitoring with Prometheus & Grafana

#### Key Metrics to Monitor

**Cluster Health:**
- `up{job="kube-apiserver"}` - API server availability
- `kube_node_status_condition{condition="Ready",status="true"}` - Node health
- `kubelet_running_pods` - Pod count by node

**Platform Services:**
- `vault_core_unsealed` - Vault seal status
- `external_secrets_sync_duration_seconds` - Secret sync latency
- `kyverno_policy_execution_duration_seconds` - Policy evaluation time

**Application Level:**
- Prometheus scrape configs auto-discover ServiceMonitors
- Add annotations to your services:
  ```yaml
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8080"
    prometheus.io/path: "/metrics"
  ```

#### Creating Alerts

Use Prometheus rules:

```bash
kubectl apply -f - <<'EOF'
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: app-alerts
  namespace: monitoring
spec:
  groups:
    - name: app
      interval: 30s
      rules:
        - alert: HighErrorRate
          expr: |
            rate(app_requests_errors_total[5m]) > 0.05
          for: 5m
          annotations:
            summary: "High error rate"
            description: "Error rate is {{ $value }}"
EOF
```

### 7. Updating Configuration

#### Modifying helmfile values

1. Edit `helmfile.yaml.gotmpl` or environment values in `helmfile.d/{env}.yaml`
2. Test locally:
   ```bash
   helmfile -e dev template | head -50  # Preview changes
   helmfile -e dev apply --diff          # See diff before applying
   ```
3. Commit and push to git
4. ArgoCD auto-syncs within 3 minutes

#### Adding a new release

1. Create release in appropriate file (e.g., `releases/myservice.yaml.gotmpl`)
2. Add to helmfile.yaml.gotmpl if not auto-discovered
3. Test: `helmfile -e dev template`
4. Commit and push
5. ArgoCD deploys automatically

### 8. Troubleshooting

#### ArgoCD stuck "Progressing"

```bash
# Check CMP plugin logs
kubectl -n argocd logs deployment/argocd-repo-server -c helmfile-cmp -f

# Common issues:
# - Missing GITHUB_TOKEN env var
# - Invalid helmfile syntax
# - Chart repository unreachable

# Test helmfile locally:
helmfile -e dev template --show-secrets 2>&1 | head -100
```

#### Vault authentication failing

```bash
# Check Kubernetes auth config
vault auth list
vault read auth/kubernetes/config

# Test auth from pod:
kubectl -n external-secrets exec -it external-secrets-xxx -- bash
vault login -method=kubernetes -path=auth/kubernetes

# Verify ESO service account exists
kubectl -n external-secrets get sa external-secrets
```

#### Kyverno blocking deployments unexpectedly

```bash
# Check if policy is in Enforce mode
kubectl get clusterpolicies

# Check violations
kubectl describe policyreport -A

# Temporarily switch to Audit mode
# Edit helmfile.d/{env}.yaml and set:
#   kyverno:
#     validationFailureAction: "audit"
# Then: helmfile -e dev apply
```

#### Metrics not appearing in Prometheus

```bash
# Check ServiceMonitor
kubectl get servicemonitor -A
kubectl describe servicemonitor -n monitoring

# Check Prometheus scrape targets
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090
# Visit http://localhost:9090/targets

# Verify ServiceMonitor labels match selector
kubectl get servicemonitor -A -o yaml | grep -A5 "selector:"
```

## Maintenance Tasks

### Weekly

- [ ] Check ExternalSecret sync status
- [ ] Review Kyverno policy reports
- [ ] Monitor Prometheus disk usage
- [ ] Check Vault unseal status

### Monthly

- [ ] Test Vault backup/restore
- [ ] Review and rotate API keys in Vault
- [ ] Update Helm chart dependencies:
  ```bash
  helm repo update
  helm search repo <chart> --versions
  ```
- [ ] Review security policies in Kyverno
- [ ] Check for Helm chart updates

### Quarterly

- [ ] Full disaster recovery test
- [ ] Review and update network policies
- [ ] Audit Vault policies and roles
- [ ] Performance tuning (replicas, resource limits)

## Backup & Recovery

### Vault Backup

```bash
# Backup Raft snapshots
kubectl -n vault exec vault-0 -- \
  vault operator raft snapshot save backup.snap

kubectl -n vault cp vault-0:/backup.snap ./backup.snap
```

### Prometheus Data Backup

```bash
# Data is stored in PVC
# Back up the PVC or S3 (if configured for long-term storage)
kubectl -n monitoring get pvc
```

### Recovery Procedures

See BOOTSTRAP.md for cluster recovery steps. Key recovery points:
1. Vault bootstrap (init, unseal, auth setup)
2. External Secrets Operator auth with Vault
3. ArgoCD self-bootstraps via app-of-apps

## Incident Response

### If all pods restart unexpectedly

1. Check node status: `kubectl get nodes`
2. Check resource usage: `kubectl top nodes`
3. Check ArgoCD sync status: `kubectl -n argocd get app`
4. Unseal Vault if needed
5. Review Kyverno policy reports (policies may be blocking pods)

### If Vault is permanently sealed

If you lost all unseal keys:
1. Delete Vault pods to wipe raft storage: `kubectl delete pod -n vault --all`
2. Delete PVCs: `kubectl delete pvc -n vault --all`
3. Re-bootstrap Vault from BOOTSTRAP.md
4. **This will lose all secrets** - restore from backup or re-create

### If ArgoCD cannot sync

1. Check git connectivity: `kubectl -n argocd logs deployment/argocd-repo-server`
2. Verify GitHub token in secret: `kubectl -n argocd get secret argocd-repo-creds`
3. Test helmfile rendering locally
4. Check firewall/network access to GitHub

## Performance Tuning

### Increase Prometheus retention

In `helmfile.d/{env}.yaml`:
```yaml
prometheus:
  retention: 90d  # Increase from default
```

### Increase Vault replicas for HA

```yaml
vault:
  replicas: 5  # Higher for larger deployments
```

### Scale Ingress NGINX

```yaml
ingressController:
  replicas: 3  # Add more for high traffic
```

## Security Best Practices

1. **Rotate secrets regularly**: `vault kv metadata delete secret/myapp/secrets`
2. **Audit Vault access**: `vault audit list` and `vault audit logs`
3. **Review RBAC**: `kubectl describe appproject platform -n argocd`
4. **Restrict network access**: Check network policies: `kubectl get networkpolicy -A`
5. **Monitor image vulnerabilities**: Check Trivy operator reports

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Helmfile Documentation](https://helmfile.readthedocs.io/)
- [HashiCorp Vault Kubernetes Auth](https://www.vaultproject.io/docs/auth/kubernetes)
- [External Secrets Operator](https://external-secrets.io/)
- [Kyverno Policies](https://kyverno.io/docs/writing-policies/)
