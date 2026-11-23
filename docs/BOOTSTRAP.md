# Bootstrap Process

## Prerequisites

- Kubernetes cluster (1.24+)
- kubectl configured to access cluster
- Helm 3.12+
- Helmfile 0.144+
- GitHub account with repo access
- HashiCorp Vault Cloud account
- 1Password account (or alternative secret backend)

## Step 1: Prepare Secrets (Manual - Secret Zero)

Create a secret file locally (DO NOT COMMIT):

```bash
mkdir -p /tmp/bootstrap-secrets
cd /tmp/bootstrap-secrets

# Generate secrets
GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"  # Classic token with repo, admin:repo_hook access
ONEPASSWORD_TOKEN="v1.xxx..."  # 1Password Service Account token
CLOUDFLARE_TOKEN="xxxx..."  # Cloudflare API token
CLOUDFLARE_ACCOUNT_ID="xxxx..."  # Cloudflare account ID

# Create secret file
cat > bootstrap-secrets.env << EOF
export GITHUB_TOKEN="${GITHUB_TOKEN}"
export ONEPASSWORD_TOKEN="${ONEPASSWORD_TOKEN}"
export CLOUDFLARE_TOKEN="${CLOUDFLARE_TOKEN}"
export CLOUDFLARE_ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID}"
EOF

chmod 600 bootstrap-secrets.env
```

## Step 2: Create ArgoCD Namespace and Secret

```bash
# Create namespace
kubectl create namespace argocd

# Load secrets
source /tmp/bootstrap-secrets/bootstrap-secrets.env

# Create secret for bootstrap
kubectl -n argocd create secret generic bootstrap-secrets \
  --from-literal=github-token="${GITHUB_TOKEN}" \
  --from-literal=onepassword-token="${ONEPASSWORD_TOKEN}" \
  --from-literal=cloudflare-token="${CLOUDFLARE_TOKEN}" \
  --from-literal=cloudflare-account-id="${CLOUDFLARE_ACCOUNT_ID}"
```

## Step 3: Install ArgoCD

```bash
# Add ArgoCD Helm repo
helm repo add argoproj https://argoproj.github.io/argo-helm
helm repo update

# Install ArgoCD (minimal, bootstrap version)
helm install argocd argoproj/argo-cd \
  --namespace argocd \
  --values bootstrap/argocd/helm-values.yaml \
  --wait
```

## Step 4: Configure ArgoCD for Helmfile Plugin

Apply the CMP plugin configuration:

```bash
kubectl patch deployment argocd-repo-server -n argocd \
  --type='json' -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/containers/0/env/-",
      "value": {
        "name": "HELMFILE_EXPERIMENTAL",
        "value": "true"
      }
    }
  ]'
```

Or use the full values override in next step.

## Step 5: Deploy Root Application (App of Apps)

```bash
# Create the root application that manages everything else
kubectl apply -f argocd/applications/app-of-apps.yaml -n argocd

# Watch ArgoCD sync
kubectl -n argocd port-forward svc/argocd-server 8080:443 &
# Open https://localhost:8080 in browser
```

## Step 6: Verify Bootstrap

```bash
# Check ArgoCD applications
kubectl -n argocd get applications

# Check if all namespaces are created
kubectl get namespaces

# Check ArgoCD repo server logs for any plugin errors
kubectl -n argocd logs -f deployment/argocd-repo-server -c helmfile-cmp

# Verify critical resources
kubectl -n cert-manager get pods  # Cert Manager
kubectl -n kyverno get pods  # Kyverno
kubectl -n monitoring get pods  # Observability
```

## Step 7: Configure Vault (Optional but Recommended)

If using HashiCorp Vault Cloud for production secrets:

```bash
# 1. Create Vault cluster in HCP

# 2. Create Kubernetes auth method
vault auth enable kubernetes

vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token

# 3. Create policy and role
vault policy write external-secrets - << EOF
path "secret/data/*" {
  capabilities = ["read", "list"]
}
EOF

vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=24h

# 4. Create ClusterSecretStore (see vault/secretstore.yaml)
kubectl apply -f vault/secretstore.yaml
```

## Step 8: Configure External DNS (Optional)

For automatic DNS management via Cloudflare:

```bash
# Ensure cloudflare token is in cluster
kubectl -n external-dns get secret cloudflare-token

# Verify external-dns is syncing:
kubectl -n external-dns logs -f deployment/external-dns
```

## Step 9: Test Helmfile Rendering

```bash
# Verify helmfile can render for each environment
helmfile -e dev template --show-secrets 2>&1 | head -50
helmfile -e staging template --show-secrets 2>&1 | head -50
helmfile -e prod template --show-secrets 2>&1 | head -50

# Validate with kubeconform
helmfile -e prod template | kubeconform -strict -ignore-missing-schemas
```

## Step 10: Set ArgoCD Admin Password

```bash
# Get initial password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Change via Web UI or CLI
argocd account update-password --account admin --new-password <new-password>

# Delete initial secret
kubectl -n argocd delete secret argocd-initial-admin-secret
```

## Step 11: Configure Notifications (Optional)

To enable Slack notifications:

```bash
# Update values in helmfile.yaml with Slack webhooks
# - argocd.notifications.enabled: true
# - slack.errorWebhook: https://hooks.slack.com/...
# - slack.warningWebhook: https://hooks.slack.com/...

helmfile -e prod sync
```

## Post-Bootstrap Checklist

- [ ] All pods in monitoring namespace running
- [ ] Grafana accessible via configured ingress
- [ ] Prometheus scraping targets healthy
- [ ] Kyverno policies in Audit mode (dev) / Enforce mode (prod)
- [ ] Falco runtime security working
- [ ] External DNS syncing records to Cloudflare
- [ ] Cert Manager provisioning certificates
- [ ] Vault authentication working (if using)
- [ ] Secrets rotating via ExternalSecret
- [ ] Slack notifications flowing
- [ ] ArgoCD syncing all applications

## Troubleshooting Bootstrap

### ArgoCD repoServer stuck "Init"
```bash
kubectl -n argocd describe deployment argocd-repo-server
kubectl -n argocd logs deployment/argocd-repo-server
```

### Helmfile plugin not found
```bash
# Verify CMP sidecar is running
kubectl -n argocd get pods -l app.kubernetes.io/name=argocd-repo-server -o yaml

# Check sidecar logs
kubectl -n argocd logs deployment/argocd-repo-server -c helmfile-cmp
```

### Certificate issues
```bash
# Check cert-manager logs
kubectl -n cert-manager logs -f deployment/cert-manager

# Check ClusterIssuer status
kubectl describe clusterissuer letsencrypt-prod
```

## Rollback

If bootstrap fails, you can rollback:

```bash
# Delete helm release
helm uninstall -n argocd argocd

# Delete namespace (cascade deletes all resources)
kubectl delete namespace argocd --cascade=background
```

Then start over from Step 2.

## Security Considerations

1. **Secret zero**: Keep bootstrap secrets in secure location, never commit to git
2. **Vault tokens**: Rotate regularly, use short TTLs in development
3. **GitHub token scopes**: Use minimal required permissions
4. **Network policies**: Once bootstrapped, verify default-deny NetworkPolicies allow API server
5. **RBAC**: Review ArgoCD projects and AppProject destination/source restrictions
