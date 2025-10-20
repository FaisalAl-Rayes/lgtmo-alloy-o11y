# ArgoCD Applications

This directory contains ArgoCD Application and ApplicationSet resources for deploying the entire multi-cluster observability stack.

## Deployment Order

Apply these resources in the following order to ensure proper dependencies:

### 1. Operators

```bash
kubectl apply -f operators-appset.yaml
```

This deploys:

- Grafana Alloy Operator to stage-cluster and prod-cluster
- Prometheus Operator to monitoring-cluster

### 2. Monitoring Stack

```bash
kubectl apply -f monitoring-stack-appset.yaml
```

This deploys to monitoring-cluster:

- Mimir (stage and prod instances)
- Loki (stage and prod instances)
- Tempo (stage and prod instances)
- Grafana with datasources

### 3. Alloy Agents

```bash
kubectl apply -f alloy-agents-appset.yaml
```

This deploys:

- Alloy agent DaemonSets to stage-cluster and prod-cluster
- Configured to send data to monitoring-cluster backends

### 4. Instrumented Applications

```bash
kubectl apply -f instrumented-apps-appset.yaml
```

This deploys:

- Instrumented applications to stage-cluster and prod-cluster
- Configured to send telemetry to local Alloy agents

### 5. Alerting Rules

```bash
kubectl apply -f alerting-rules-app.yaml
```

This deploys:

- PrometheusRule CRDs to monitoring-cluster
- Alerting rules for metrics and logs

## Configuration

Before applying these resources, update the `repoURL` field in each file to point to your Git repository.

## Sync Policy

All applications are configured with automated sync:

- `prune: true` - Remove resources that are no longer defined
- `selfHeal: true` - Automatically sync when cluster state differs from Git
- `CreateNamespace=true` - Automatically create namespaces if they don't exist

## Accessing Services

After deployment, access services using NodePort:

- **Grafana**: `http://$(minikube ip -p monitoring-cluster):30300`
- **Instrumented App (Stage)**: `http://$(minikube ip -p stage-cluster):30800`
- **Instrumented App (Prod)**: `http://$(minikube ip -p prod-cluster):30800`
