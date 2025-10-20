# PrometheusRule Label Strategy

## Required Labels

All PrometheusRule CRDs in this directory MUST have these labels:

```yaml
metadata:
  labels:
    tenant: <tenant-id> # Required: Which tenant (stage, prod, etc.)
    type: <rule-type> # Required: Rule type (metrics or logs)
    prometheus: monitoring # Standard: Prometheus Operator compatibility
```

## Label Definitions

### `tenant` Label

**Purpose:** Determines which tenant's ruler will receive and evaluate these rules.

**Values:**

- `stage` - Development/staging environment
- `prod` - Production environment
- `<custom>` - Any custom tenant you configure

**How it's used:**

- Alloy-Alerts uses this label to route rules to the correct Mimir tenant
- Each tenant has isolated rule storage: `/data/mimir/rules/<tenant>/`
- Rules are evaluated only against that tenant's metrics

**Example:**

```yaml
labels:
  tenant: prod # This rule goes to prod tenant's Mimir ruler
```

### `type` Label

**Purpose:** Distinguishes between different types of alerting rules.

**Values:**

- `metrics` - Rules that query metrics using PromQL (evaluated by Mimir ruler)
- `logs` - Rules that query logs using LogQL (evaluated by Loki ruler) [Future]

**Why this matters:**

1. **Organization**: Easy to see which rules are for metrics vs logs
2. **Routing**: Can route different rule types to different systems
3. **Filtering**: Can filter PrometheusRule CRDs by type in queries
4. **Future-proofing**: Prepares for log-based alerting rules

**Example:**

```yaml
# Metrics-based rule
labels:
  type: metrics
spec:
  groups:
    - name: app.metrics
      rules:
        - alert: HighCPU
          expr: cpu_usage > 80 # ← PromQL query

---
# Log-based rule (future)
labels:
  type: logs
spec:
  groups:
    - name: app.logs
      rules:
        - alert: ErrorSpike
          expr: |
            sum(rate({level="error"}[5m])) > 100  # ← LogQL query
```

### `prometheus` Label

**Purpose:** Standard label for Prometheus Operator compatibility.

**Value:** Always `monitoring` (the namespace where monitoring components run)

**Why it exists:**

- Required by Prometheus Operator for rule discovery
- Even though we're using Mimir (not Prometheus), we keep this for compatibility
- Allows tools that expect Prometheus Operator format to work

## Label Matrix

| Tenant | Type    | Use Case           | Example Alert              |
| ------ | ------- | ------------------ | -------------------------- |
| stage  | metrics | Stage app metrics  | HighErrorRate (>5%)        |
| stage  | logs    | Stage log patterns | ErrorLogSpike (>50/min)    |
| prod   | metrics | Prod app metrics   | HighErrorRate (>2%)        |
| prod   | logs    | Prod log patterns  | CriticalLogSpike (>10/min) |

## Filtering Rules

### By Tenant

```bash
# List all prod rules
kubectl get prometheusrules -l tenant=prod

# List all stage rules
kubectl get prometheusrules -l tenant=stage
```

### By Type

```bash
# List all metrics rules
kubectl get prometheusrules -l type=metrics

# List all log rules (future)
kubectl get prometheusrules -l type=logs
```

### Combined Filters

```bash
# List prod metrics rules only
kubectl get prometheusrules -l tenant=prod,type=metrics

# List stage log rules only (future)
kubectl get prometheusrules -l tenant=stage,type=logs
```

## Alloy-Alerts Configuration

The Alloy-Alerts component uses these labels to route rules:

```hcl
// Routes metrics rules for prod tenant to Mimir
mimir.rules.kubernetes "prod_rules" {
  address   = "http://mimir:9009"
  tenant_id = "prod"

  rule_selector {
    match_labels = {
      tenant = "prod"  # ← Filters by tenant label
      // Note: Currently doesn't filter by type,
      // but could be added for more precise routing
    }
  }
}
```

**Future enhancement:** Could filter by type:

```hcl
// For metrics rules to Mimir
rule_selector {
  match_labels = {
    tenant = "prod"
    type   = "metrics"  # ← Only sync metrics rules to Mimir
  }
}

// For log rules to Loki
loki.rules.kubernetes "prod_log_rules" {
  address   = "http://loki:3100"
  tenant_id = "prod"

  rule_selector {
    match_labels = {
      tenant = "prod"
      type   = "logs"  # ← Only sync log rules to Loki
    }
  }
}
```

## Best Practices

1. **Always include both required labels**: `tenant` and `type`
2. **Use consistent values**: Don't create custom values without updating Alloy config
3. **Naming convention**: Include type in filename for clarity
   - `app-alerts-prod.yaml` → `app-metrics-alerts-prod.yaml`
   - `log-alerts-prod.yaml` (future)
4. **Keep rules separated**: Don't mix metrics and log rules in same file
5. **Document custom tenants**: If adding new tenants, update this doc

## Examples

### ✅ Good - All required labels

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: app-metrics-alerts-prod
  labels:
    tenant: prod
    type: metrics
    prometheus: monitoring
```

### ❌ Bad - Missing type label

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: app-alerts-prod
  labels:
    tenant: prod
    # Missing: type label
    prometheus: monitoring
```

### ❌ Bad - Wrong type value

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: app-alerts-prod
  labels:
    tenant: prod
    type: prometheus # ← Wrong! Should be "metrics" or "logs"
    prometheus: monitoring
```

## Migration Guide

If you have existing PrometheusRule CRDs without the `type` label:

```bash
# Add type label to existing rules
kubectl label prometheusrule app-alerts-stage type=metrics -n monitoring
kubectl label prometheusrule app-alerts-prod type=metrics -n monitoring
```

Or update the YAML files and re-apply:

```bash
kubectl apply -f o11y/alerting-rules/tenants/stage/
kubectl apply -f o11y/alerting-rules/tenants/prod/
```
