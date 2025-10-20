# Alloy-Alerts Architecture

## Why a Separate Component?

The `alloy-alerts` component is dedicated to managing alert rules, separate from metrics, logs, and traces collection. This provides:

### 1. **Separation of Concerns**

Each Alloy component has a single, clear responsibility:

| Component          | Responsibility                            |
| ------------------ | ----------------------------------------- |
| `alloy-metrics`    | Scrape and forward metrics to Mimir       |
| `alloy-logs`       | Collect and forward logs to Loki          |
| `alloy-traces`     | Collect and forward traces to Tempo       |
| **`alloy-alerts`** | **Sync alert rules to Mimir/Loki rulers** |

### 2. **Independent Lifecycle**

- **Updates**: Can update alert rule syncing without restarting metrics collection
- **Scaling**: Can scale rule syncing independently (though typically needs only 1 replica)
- **Debugging**: Easier to troubleshoot when issues are isolated
- **Resource Allocation**: Different resource requirements

### 3. **Failure Isolation**

If alert rule syncing has issues:

- ✅ Metrics collection continues unaffected
- ✅ Logs collection continues unaffected
- ✅ Existing alerts in Mimir continue to evaluate
- ❌ Only new/updated rules won't sync until fixed

### 4. **Clear Ownership**

```
┌─────────────────────────────────────────────────────────────────┐
│                    Observability Pipeline                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │ alloy-metrics│  │  alloy-logs  │  │ alloy-traces │         │
│  │              │  │              │  │              │         │
│  │ Metrics →    │  │ Logs →       │  │ Traces →     │         │
│  │   Mimir      │  │   Loki       │  │   Tempo      │         │
│  └──────────────┘  └──────────────┘  └──────────────┘         │
│                                                                  │
│  ┌────────────────────────────────────────────────────┐        │
│  │            alloy-alerts                            │        │
│  │                                                     │        │
│  │  PrometheusRule CRDs → Mimir Ruler (per tenant)  │        │
│  │  (Future: LoggingRule CRDs → Loki Ruler)         │        │
│  └────────────────────────────────────────────────────┘        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Architecture Flow

### Complete Alert Lifecycle

```
┌────────────────────────────────────────────────────────────────┐
│ 1. Developer writes PrometheusRule CRD                          │
│    kubectl apply -f app-alerts-prod.yaml                        │
└──────────────────────┬─────────────────────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────────────────────┐
│ 2. Kubernetes API Server stores the CRD                         │
│    PrometheusRule with label: tenant=prod                       │
└──────────────────────┬─────────────────────────────────────────┘
                       │
                       │ Watches via K8s API
                       ▼
┌────────────────────────────────────────────────────────────────┐
│ 3. Alloy-Alerts detects the new/changed rule                   │
│    mimir.rules.kubernetes "prod_rules" component               │
│    - Filters by label: tenant=prod                             │
│    - Converts to Mimir ruler format                            │
└──────────────────────┬─────────────────────────────────────────┘
                       │
                       │ POST to Mimir API
                       │ Header: X-Scope-OrgID: prod
                       ▼
┌────────────────────────────────────────────────────────────────┐
│ 4. Mimir Ruler receives and stores the rule                    │
│    /data/mimir/rules/prod/                                     │
│    - Stored separately per tenant                              │
└──────────────────────┬─────────────────────────────────────────┘
                       │
                       │ Queries tenant metrics
                       ▼
┌────────────────────────────────────────────────────────────────┐
│ 5. Mimir Ruler evaluates rules periodically                    │
│    - Every 30s (or as configured)                              │
│    - Queries only prod tenant's metrics                        │
│    - Checks if threshold exceeded                              │
└──────────────────────┬─────────────────────────────────────────┘
                       │
                       │ If alert fires
                       ▼
┌────────────────────────────────────────────────────────────────┐
│ 6. Alert sent to Mimir AlertManager                            │
│    - Routed to prod tenant's AlertManager config               │
│    - Grouped, deduplicated, inhibited                          │
└──────────────────────┬─────────────────────────────────────────┘
                       │
                       │ Based on routing rules
                       ▼
┌────────────────────────────────────────────────────────────────┐
│ 7. Notification sent                                           │
│    - PagerDuty (for critical)                                  │
│    - Slack (for all)                                           │
│    - Email (optional)                                          │
└────────────────────────────────────────────────────────────────┘
```

## Component Internals

### Alloy-Alerts Configuration

```hcl
// Watch stage tenant rules
mimir.rules.kubernetes "stage_rules" {
  address   = "http://mimir.monitoring.svc.cluster.local:9009"
  tenant_id = "stage"

  // Only sync rules with this label
  rule_selector {
    match_labels = {
      tenant = "stage"
    }
  }

  // Only watch this namespace
  rule_namespace_selector {
    match_labels = {
      "kubernetes.io/metadata.name" = "monitoring"
    }
  }
}

// Watch prod tenant rules
mimir.rules.kubernetes "prod_rules" {
  address   = "http://mimir.monitoring.svc.cluster.local:9009"
  tenant_id = "prod"

  rule_selector {
    match_labels = {
      tenant = "prod"
    }
  }

  rule_namespace_selector {
    match_labels = {
      "kubernetes.io/metadata.name" = "monitoring"
    }
  }
}
```

### How It Works

1. **Kubernetes Watch**: Uses Kubernetes watch API to monitor PrometheusRule CRDs
2. **Label Matching**: Filters rules based on label selectors
3. **Format Conversion**: Converts PrometheusRule spec to Mimir ruler format
4. **API Sync**: POSTs rules to Mimir ruler API with tenant header
5. **Continuous Reconciliation**: Keeps Mimir in sync with Kubernetes state

### What Happens When...

#### A new rule is created

```bash
kubectl apply -f app-alerts-prod.yaml
```

1. Alloy-Alerts detects the new CRD
2. Converts it to Mimir format
3. POSTs to Mimir API with `X-Scope-OrgID: prod`
4. Mimir stores in `/data/mimir/rules/prod/`
5. Mimir ruler starts evaluating immediately

#### A rule is updated

```bash
kubectl apply -f app-alerts-prod.yaml  # Changed threshold
```

1. Alloy-Alerts detects the change
2. Updates the rule in Mimir
3. Mimir ruler picks up the change on next evaluation

#### A rule is deleted

```bash
kubectl delete prometheusrule app-alerts-prod
```

1. Alloy-Alerts detects the deletion
2. Removes the rule from Mimir
3. Active alerts from that rule will clear after timeout

## Deployment Patterns

### Single Cluster

```
┌──────────────────────────────────────┐
│         Kubernetes Cluster            │
│                                       │
│  ┌─────────────┐                     │
│  │ alloy-alerts│──────┐              │
│  │ (1 replica) │      │              │
│  └─────────────┘      │              │
│                       ▼              │
│  ┌──────────────────────────────┐   │
│  │        Mimir                  │   │
│  │  ┌────────┐  ┌────────┐      │   │
│  │  │ stage  │  │  prod  │      │   │
│  │  └────────┘  └────────┘      │   │
│  └──────────────────────────────┘   │
└──────────────────────────────────────┘
```

### Multi-Cluster (Federation)

```
┌─────────────────────┐  ┌─────────────────────┐
│   Stage Cluster     │  │   Prod Cluster      │
│                     │  │                     │
│  ┌──────────────┐  │  │  ┌──────────────┐  │
│  │alloy-alerts  │  │  │  │alloy-alerts  │  │
│  │(stage rules) │──┼──┼─▶│(prod rules)  │  │
│  └──────────────┘  │  │  └──────────────┘  │
└─────────────────────┘  └──────────────────┬─┘
                                             │
                         ┌───────────────────▼───┐
                         │  Central Mimir         │
                         │  - Multi-tenant        │
                         │  - Federated rules     │
                         └────────────────────────┘
```

## Resource Requirements

### Typical Resource Usage

```yaml
resources:
  requests:
    cpu: 50m # Very light - just watches K8s API
    memory: 64Mi # Minimal memory footprint
  limits:
    cpu: 200m # Burst for rule conversion
    memory: 256Mi # Room for large rule sets
```

### When to Scale

Generally, **1 replica is sufficient** because:

- Watching K8s API is lightweight
- Rule syncing happens infrequently
- Alloy handles reconnection automatically

Scale to **2+ replicas** only if:

- You have thousands of PrometheusRule CRDs
- You need high availability for rule updates
- You're managing rules across many namespaces

## Monitoring Alloy-Alerts

### Key Metrics

```promql
# Is alloy-alerts running?
up{job="alloy-alerts"}

# Rule sync operations
alloy_mimir_rules_kubernetes_syncs_total

# Rule sync failures
alloy_mimir_rules_kubernetes_sync_failures_total

# Number of rules currently synced
alloy_mimir_rules_kubernetes_rules_count
```

### Health Check

```bash
# Check pod status
kubectl get pods -n alloy-system -l app=alloy-alerts

# Check recent logs
kubectl logs -n alloy-system -l app=alloy-alerts --tail=100

# Check if rules are syncing
kubectl logs -n alloy-system -l app=alloy-alerts | grep -i "synced"
```

## Comparison: Before vs After

### Before (Monolithic)

```
❌ alloy-metrics:
   - Scrapes metrics
   - Forwards to Mimir
   - Syncs alert rules  ← Mixed responsibilities
```

**Problems:**

- Metrics collection affected by rule sync issues
- Harder to debug
- Unclear ownership
- Complex configuration

### After (Separated)

```
✅ alloy-metrics:
   - Scrapes metrics
   - Forwards to Mimir

✅ alloy-alerts:
   - Syncs alert rules  ← Single responsibility
```

**Benefits:**

- Clear separation
- Independent failures
- Easier debugging
- Simpler configurations

## Future Enhancements

1. **Loki Rules**: Add support for syncing log-based alerting rules to Loki ruler
2. **Multi-Namespace**: Watch PrometheusRules across multiple namespaces
3. **Validation**: Validate rules before syncing to catch errors early
4. **Metrics**: Export detailed metrics about rule sync operations
5. **Status Updates**: Update PrometheusRule CRD status with sync state

## Summary

The `alloy-alerts` component provides:

✅ **Dedicated alert rule management**
✅ **Clean separation from data collection**
✅ **Multi-tenant rule syncing**
✅ **Kubernetes-native workflow**
✅ **Failure isolation**
✅ **Easy to operate and debug**

This architecture follows the Unix philosophy: "Do one thing and do it well."
