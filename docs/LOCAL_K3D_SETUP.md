# Local Kubernetes Cluster Setup with k3d

This guide explains how to spin up and manage a local lightweight Kubernetes (k3s) cluster inside Docker containers using k3d and kubectl.

## 📋 Prerequisites

Before proceeding, ensure you have:

- macOS with Homebrew installed
- Docker (Docker Desktop, OrbStack, or Colima) installed and currently running

## 🚀 1. Install CLI Tools

Install `kubectl` (Kubernetes command-line tool) and `k3d` via Homebrew:

```bash
brew install kubectl k3d
```

Verify that both tools are installed properly:

```bash
kubectl version --client && k3d --version
```

## 🏗️ 2. Create the Cluster

Create a local multi-node cluster named `gitops-local` with 1 server (control plane), 2 agents (worker nodes), and mapped ports for an Ingress controller / Load Balancer:

```bash
k3d cluster create gitops-local \
  --servers 1 \
  --agents 2 \
  --port "80:80@loadbalancer" \
  --port "443:443@loadbalancer"
```

### Parameter Breakdown

| Parameter | Description |
|-----------|-------------|
| `gitops-local` | Name of the cluster |
| `--servers 1` | Provisions 1 control-plane node (server) |
| `--agents 2` | Provisions 2 worker nodes (agents) |
| `--port "80:80@loadbalancer"` | Maps host port 80 to the built-in Traefik load balancer port 80 (HTTP) |
| `--port "443:443@loadbalancer"` | Maps host port 443 to the load balancer port 443 (HTTPS) |

## 🔐 3. Configure Kubeconfig & Context

By default, k3d updates your kubeconfig automatically upon creation. If you need to export or merge the kubeconfig into your default `~/.kube/config` and switch contexts:

```bash
# Merge cluster config and switch current context
k3d kubeconfig merge gitops-local --kubeconfig-switch-context
```

To view or print the cluster's kubeconfig directly:

```bash
k3d kubeconfig get gitops-local
```

### Verify Cluster Nodes

Check that all nodes are ready:

```bash
kubectl get nodes -o wide
```

## 🛠️ 4. Useful k3d Management Commands

### List Clusters

List all running k3d clusters:

```bash
k3d cluster list
```

### Stop / Start Cluster

Save resources by stopping the cluster when not in use:

```bash
# Stop cluster
k3d cluster stop gitops-local

# Start cluster
k3d cluster start gitops-local
```

### Delete Cluster

When you are done and want to tear down the cluster and its containers:

```bash
k3d cluster delete gitops-local
```

## 📌 Quick Reference

| Command | Purpose |
|---------|---------|
| `k3d cluster create gitops-local --servers 1 --agents 2 --port "80:80@loadbalancer" --port "443:443@loadbalancer"` | Create a new k3d cluster |
| `k3d kubeconfig merge gitops-local --kubeconfig-switch-context` | Merge kubeconfig and switch context |
| `kubectl get nodes -o wide` | Verify all nodes are ready |
| `k3d cluster list` | List all clusters |
| `k3d cluster stop gitops-local` | Stop the cluster |
| `k3d cluster start gitops-local` | Start the cluster |
| `k3d cluster delete gitops-local` | Delete the cluster |
