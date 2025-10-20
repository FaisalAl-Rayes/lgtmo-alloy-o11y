# Multi-Tenant Alert Rules

This directory contains per-tenant PrometheusRule CRDs that are automatically synced to Mimir's ruler by Alloy.

## Directory Structure

```
tenants/
├── stage/
│   ├── app-alerts-stage.yaml           # Stage tenant METRICS alert rules
│   └── (future) log-alerts-stage.yaml  # Stage tenant LOG alert rules
└── prod/
    ├── app-alerts-prod.yaml            # Prod tenant METRICS alert rules
    └── (future) log-alerts-prod.yaml   # Prod tenant LOG alert rules
```

**Note:** Currently, only metrics-based rules (`type: metrics`) are implemented. Log-based rules (`type: logs`) will be added in the future when Loki ruler integration is configured.

## How It Works

1. **PrometheusRule CRDs** are created with tenant-specific labels
2. **Alloy** watches these CRDs and syncs them to Mimir's ruler API
3. **Mimir's ruler** evaluates the rules against tenant-specific data
4. **Mimir's AlertManager** receives and routes alerts based on tenant

## Creating Tenant-Specific Rules

### Required Labels

Each PrometheusRule must have the `tenant` and `type` labels:

```yaml
metadata:
  labels:
    tenant: stage # or "prod" - matches your tenant ID
    type: metrics # "metrics" or "logs" - distinguishes rule type
    prometheus: monitoring
```

**Label Meanings:**

- `tenant`: Determines which tenant's Mimir ruler will receive the rules
- `type`: Distinguishes between metrics-based and log-based alerting rules
- `prometheus`: Standard label for Prometheus Operator compatibility

### Rule Differences Between Tenants

**Stage (Development/Testing):**

- More lenient thresholds (e.g., 5% error rate)
- Longer evaluation times (e.g., 2-3 minutes)
- Lower severity (warning vs critical)
- Shorter for clause

**Prod (Production):**

- Stricter thresholds (e.g., 2% error rate)
- Longer evaluation times for stability (5+ minutes)
- Higher severity (critical)
- Includes runbook URLs for incident response

## Deployment

### Option 1: Apply Directly

```bash
# Deploy stage rules
kubectl apply -f o11y/alerting-rules/tenants/stage/

# Deploy prod rules
kubectl apply -f o11y/alerting-rules/tenants/prod/
```

### Option 2: Use Kustomize

Create a `kustomization.yaml` in each tenant directory and deploy via ArgoCD or Flux.

## Verification

Check if rules are synced to Mimir:

```bash
# Port-forward Mimir
kubectl port-forward -n monitoring svc/mimir 9009:9009

# Check stage tenant rules
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/prometheus/api/v1/rules | jq

# Check prod tenant rules
curl -H "X-Scope-OrgID: prod" \
  http://localhost:9009/prometheus/api/v1/rules | jq
```

## Alert Labels

Always include these labels in your alert rules:

```yaml
labels:
  severity: critical|warning|info
  tenant: stage|prod
  component: your-component-name
```

These labels are used for:

- **severity**: Alert routing and inhibition rules
- **tenant**: Multi-tenant isolation and routing
- **component**: Grouping and filtering in AlertManager UI

## Adding New Tenants

1. Create a new directory: `tenants/<tenant-name>/`
2. Add PrometheusRule CRDs with `tenant: <tenant-name>` label
3. Update Alloy configuration to add a new `mimir.rules.kubernetes` block for the tenant
4. Configure AlertManager routing for the new tenant

## Log-Based Alert Rules

Log-based alerting rules work exactly like metrics rules! Just create PrometheusRule CRDs with `type: logs`:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: log-alerts-prod
  namespace: monitoring
  labels:
    tenant: prod
    type: logs # ← Log-based rules
    prometheus: monitoring
spec:
  groups:
    - name: prod.log.alerts
      interval: 1m
      rules:
        - alert: HighErrorLogRate
          expr: |
            sum(rate({level="error"}[5m])) by (app) > 5  # ← LogQL query
          for: 5m
          labels:
            severity: critical
            tenant: prod
            type: logs
          annotations:
            summary: "High error log rate in {{ $labels.app }}"
```

**How it works:**

1. Create PrometheusRule CRD with `type: logs` label
2. Alloy-Alerts `loki.rules.kubernetes` component watches for these
3. Rules automatically sync to Loki's ruler (per tenant)
4. Loki evaluates LogQL queries and fires alerts
5. Alerts go to Mimir's multi-tenant AlertManager

**Just apply the CRDs - no manual steps needed!**

```bash
kubectl apply -f o11y/alerting-rules/tenants/stage/log-alerts-stage.yaml
kubectl apply -f o11y/alerting-rules/tenants/prod/log-alerts-prod.yaml
```

## Best Practices

1. **Use descriptive alert names**: `HighErrorRate`, `ServiceDown`, etc.
2. **Include context in annotations**: Environment, instance, actual values
3. **Add runbook URLs**: Help responders know what to do
4. **Test alerts**: Trigger test alerts before deploying to production
5. **Monitor your monitoring**: Set up alerts for Mimir/Alloy/AlertManager itself
6. **Use the `type` label consistently**: `metrics` for PromQL, `logs` for LogQL queries
