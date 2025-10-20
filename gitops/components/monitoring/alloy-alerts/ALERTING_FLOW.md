# Complete Multi-Tenant Alerting Flow

This document explains how metrics-based and log-based alerting rules flow through the system from PrometheusRule CRDs to notifications.

## Overview

Both metrics and log alerts use:

- **Same CRD format**: PrometheusRule (Kubernetes native)
- **Same AlertManager**: Mimir's multi-tenant AlertManager
- **Different Rulers**: Mimir ruler for metrics, Loki ruler for logs

## Complete Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    PrometheusRule CRDs (Kubernetes)                  │
│                                                                      │
│  ┌──────────────────────────┐    ┌──────────────────────────┐     │
│  │ Metrics Alert Rules       │    │ Log Alert Rules          │     │
│  │                           │    │                           │     │
│  │ metadata:                 │    │ metadata:                 │     │
│  │   labels:                 │    │   labels:                 │     │
│  │     tenant: stage         │    │     tenant: stage         │     │
│  │     type: metrics         │    │     type: logs            │     │
│  │                           │    │                           │     │
│  │ spec:                     │    │ spec:                     │     │
│  │   expr: |                 │    │   expr: |                 │     │
│  │     rate(errors[5m]) > 5  │    │     rate({level="error"}) │     │
│  │     ↑ PromQL              │    │     ↑ LogQL               │     │
│  └────────────┬──────────────┘    └────────────┬──────────────┘     │
└───────────────┼──────────────────────────────────┼──────────────────┘
                │                                  │
                │ Watched by Alloy-Alerts          │
                ▼                                  ▼
┌───────────────────────────────────────────────────────────────────────┐
│                         ALLOY-ALERTS Component                         │
│                                                                        │
│  ┌────────────────────────┐        ┌────────────────────────┐        │
│  │ mimir.rules.kubernetes │        │ loki.rules.kubernetes  │        │
│  │                        │        │                        │        │
│  │ address = MIMIR_ENDPOINT│       │ address = LOKI_ENDPOINT│        │
│  │ tenant_id = "stage"    │        │ tenant_id = "stage"    │        │
│  │                        │        │                        │        │
│  │ rule_selector:         │        │ rule_selector:         │        │
│  │   tenant = "stage"     │        │   tenant = "stage"     │        │
│  │   type = "metrics"     │        │   type = "logs"        │        │
│  └────────────┬───────────┘        └────────────┬───────────┘        │
└───────────────┼────────────────────────────────────┼──────────────────┘
                │ Syncs rules                        │ Syncs rules
                │ via API                            │ via API
                ▼                                    ▼
┌─────────────────────────┐          ┌─────────────────────────┐
│   MIMIR (port 9009)     │          │   LOKI (port 3100)      │
│                         │          │                         │
│  ┌──────────────────┐   │          │  ┌──────────────────┐   │
│  │  Mimir Ruler     │   │          │  │  Loki Ruler      │   │
│  │                  │   │          │  │                  │   │
│  │ • Stores rules   │   │          │  │ • Stores rules   │   │
│  │   per tenant     │   │          │  │   per tenant     │   │
│  │ • Evaluates      │   │          │  │ • Evaluates      │   │
│  │   PromQL queries │   │          │  │   LogQL queries  │   │
│  │ • Queries metrics│   │          │  │ • Queries logs   │   │
│  │   data           │   │          │  │   data           │   │
│  └────────┬─────────┘   │          │  └────────┬─────────┘   │
│           │             │          │           │             │
│           │ Fires alerts│          │           │ Fires alerts│
│           ▼             │          │           ▼             │
│  ┌──────────────────┐   │          │  alertmanager_url:     │
│  │ Mimir            │◄──┼──────────┼──http://mimir:9009/    │
│  │ AlertManager     │   │          │  alertmanager          │
│  │                  │   │          │                         │
│  │ • Multi-tenant   │   │          └─────────────────────────┘
│  │ • Receives alerts│   │
│  │   from both      │   │
│  │   Mimir & Loki   │   │
│  │ • Deduplicates   │   │
│  │ • Groups alerts  │   │
│  │ • Routes by      │   │
│  │   tenant         │   │
│  └────────┬─────────┘   │
└───────────┼─────────────┘
            │
            │ Send notifications
            ▼
┌────────────────────────────────────┐
│        Notification Channels        │
│                                    │
│  ┌──────────┐  ┌──────────┐      │
│  │  Slack   │  │ PagerDuty │      │
│  └──────────┘  └──────────┘      │
│  ┌──────────┐  ┌──────────┐      │
│  │  Email   │  │ Webhook  │      │
│  └──────────┘  └──────────┘      │
└────────────────────────────────────┘
```

## Key Concepts

### Why Different Endpoints?

**Question**: Why does Alloy need both MIMIR_ENDPOINT and LOKI_ENDPOINT if alerts all go to Mimir's AlertManager?

**Answer**: Because rulers and AlertManager are different components with different responsibilities:

| Component              | Responsibility                    | Needs                            |
| ---------------------- | --------------------------------- | -------------------------------- |
| **Mimir Ruler**        | Evaluate PromQL (metrics queries) | Access to Mimir's metrics data   |
| **Loki Ruler**         | Evaluate LogQL (log queries)      | Access to Loki's log data        |
| **Mimir AlertManager** | Route and send notifications      | Receives alerts from BOTH rulers |

### Data Flow for Metrics Alerts

1. **Developer** creates PrometheusRule with `type: metrics`
2. **Alloy-Alerts** watches Kubernetes API, detects new rule
3. **Alloy** syncs rule to **Mimir ruler** via `MIMIR_ENDPOINT`
4. **Mimir ruler** evaluates PromQL query against metrics data
5. If threshold exceeded, **Mimir ruler** fires alert
6. Alert sent to **Mimir AlertManager** (same process, localhost)
7. **AlertManager** routes notification based on tenant config

### Data Flow for Log Alerts

1. **Developer** creates PrometheusRule with `type: logs`
2. **Alloy-Alerts** watches Kubernetes API, detects new rule
3. **Alloy** syncs rule to **Loki ruler** via `LOKI_ENDPOINT`
4. **Loki ruler** evaluates LogQL query against log data
5. If threshold exceeded, **Loki ruler** fires alert
6. Alert sent to **Mimir AlertManager** via configured URL
7. **AlertManager** routes notification based on tenant config

## Configuration Details

### Alloy-Alerts Environment Variables

```yaml
extraEnv:
  - name: MIMIR_ENDPOINT
    value: "mimir.monitoring.svc.cluster.local:9009"
  - name: LOKI_ENDPOINT
    value: "loki.monitoring.svc.cluster.local:3100"
```

### Mimir Configuration

```yaml
# Mimir ruler sends alerts to its own AlertManager
ruler:
  enable_api: true
  alertmanager_url: http://localhost:9009/alertmanager
  rule_path: /data/mimir/rules-data

# Mimir's multi-tenant AlertManager
alertmanager:
  enable_api: true
  data_dir: /data/mimir/alertmanager
  external_url: http://mimir:9009/alertmanager
  fallback_config_file: /etc/mimir-alertmanager/alertmanager-fallback.yaml

alertmanager_storage:
  backend: filesystem
  filesystem:
    dir: /data/mimir/alertmanager-configs
```

### Loki Configuration

```yaml
# Loki ruler sends alerts to Mimir's AlertManager
ruler:
  alertmanager_url: http://mimir.monitoring.svc.cluster.local:9009/alertmanager
  enable_api: true
  enable_alertmanager_v2: true
  storage:
    type: local
    local:
      directory: /loki/rules
```

## Multi-Tenancy

### Per-Tenant Isolation

```
Tenant: stage
├── Mimir ruler storage: /data/mimir/rules/stage/
├── Loki ruler storage: /loki/rules/stage/
└── AlertManager config: per-tenant routing in Mimir

Tenant: prod
├── Mimir ruler storage: /data/mimir/rules/prod/
├── Loki ruler storage: /loki/rules/prod/
└── AlertManager config: per-tenant routing in Mimir
```

### Rule Evaluation Isolation

**Mimir Ruler**:

- Stage tenant rules only query stage tenant's metrics
- Prod tenant rules only query prod tenant's metrics
- Controlled by `X-Scope-OrgID` header

**Loki Ruler**:

- Stage tenant rules only query stage tenant's logs
- Prod tenant rules only query prod tenant's logs
- Controlled by `X-Scope-OrgID` header

### Alert Routing

All alerts flow to the same Mimir AlertManager, but routing is tenant-aware:

```yaml
# Mimir AlertManager fallback config
route:
  group_by: ["alertname", "tenant", "cluster"]
  receiver: "default-receiver"

  routes:
    # Route stage alerts
    - receiver: "stage-receiver"
      matchers:
        - tenant="stage"

    # Route prod alerts
    - receiver: "prod-receiver"
      matchers:
        - tenant="prod"
```

## Example: Alert Lifecycle

### Metrics Alert Lifecycle

```
1. kubectl apply -f app-alerts-prod.yaml
   ↓
2. PrometheusRule CRD created with:
   - tenant: prod
   - type: metrics
   - expr: rate(errors[5m]) > 0.02
   ↓
3. Alloy-Alerts detects new rule via Kubernetes watch
   ↓
4. mimir.rules.kubernetes component filters:
   - Match: tenant=prod AND type=metrics ✓
   ↓
5. Alloy syncs to Mimir:
   POST http://mimir:9009/prometheus/config/v1/rules/prod
   Header: X-Scope-OrgID: prod
   ↓
6. Mimir ruler stores in: /data/mimir/rules/prod/
   ↓
7. Mimir ruler evaluates every 30s:
   - Queries prod tenant's metrics only
   - Checks: rate(errors[5m]) > 0.02
   ↓
8. If threshold exceeded:
   - Fires alert to http://localhost:9009/alertmanager
   - Alert includes label: tenant=prod
   ↓
9. Mimir AlertManager receives alert:
   - Matches route for tenant=prod
   - Groups with other prod alerts
   - Sends to prod-receiver (PagerDuty)
```

### Log Alert Lifecycle

```
1. kubectl apply -f log-alerts-prod.yaml
   ↓
2. PrometheusRule CRD created with:
   - tenant: prod
   - type: logs
   - expr: rate({level="error"}[5m]) > 5
   ↓
3. Alloy-Alerts detects new rule via Kubernetes watch
   ↓
4. loki.rules.kubernetes component filters:
   - Match: tenant=prod AND type=logs ✓
   ↓
5. Alloy syncs to Loki:
   POST http://loki:3100/loki/api/v1/rules/prod
   Header: X-Scope-OrgID: prod
   ↓
6. Loki ruler stores in: /loki/rules/prod/
   ↓
7. Loki ruler evaluates every 1m:
   - Queries prod tenant's logs only
   - Checks: rate({level="error"}[5m]) > 5
   ↓
8. If threshold exceeded:
   - Fires alert to http://mimir:9009/alertmanager
   - Alert includes labels: tenant=prod, type=logs
   ↓
9. Mimir AlertManager receives alert:
   - Matches route for tenant=prod
   - Groups with other prod alerts
   - Sends to prod-receiver (PagerDuty)
```

## Verification Commands

### Check if rules are synced

```bash
# Port-forward services
kubectl port-forward -n monitoring svc/mimir 9009:9009
kubectl port-forward -n monitoring svc/loki 3100:3100

# Check Mimir metrics rules for stage tenant
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/prometheus/api/v1/rules | jq

# Check Mimir metrics rules for prod tenant
curl -H "X-Scope-OrgID: prod" \
  http://localhost:9009/prometheus/api/v1/rules | jq

# Check Loki log rules for stage tenant
curl -H "X-Scope-OrgID: stage" \
  http://localhost:3100/loki/api/v1/rules | jq

# Check Loki log rules for prod tenant
curl -H "X-Scope-OrgID: prod" \
  http://localhost:3100/loki/api/v1/rules | jq
```

### Check active alerts

```bash
# Check all alerts in Mimir AlertManager for stage
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/alertmanager/api/v2/alerts | jq

# Check all alerts in Mimir AlertManager for prod
curl -H "X-Scope-OrgID: prod" \
  http://localhost:9009/alertmanager/api/v2/alerts | jq

# Check Mimir ruler alerts specifically
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/prometheus/api/v1/alerts | jq

# Check Loki ruler alerts specifically
curl -H "X-Scope-OrgID: stage" \
  http://localhost:3100/loki/api/v1/rules/alerts | jq
```

## Common Questions

### Q: Why not have separate AlertManagers?

**A**: Using one unified AlertManager provides:

- Single place for alert configuration
- Unified view of all alerts (metrics + logs)
- Consistent routing and notification policies
- Easier correlation of related alerts
- Simplified troubleshooting

### Q: Can I use different AlertManagers per tenant?

**A**: Yes! Configure per-tenant AlertManager URLs:

- Each tenant can have their own AlertManager config in Mimir
- Upload via API with `X-Scope-OrgID` header
- Supports completely isolated notification channels

### Q: What if I only want metrics OR logs alerts?

**A**: Just don't create PrometheusRules with the `type` you don't want:

- Only create `type: metrics` rules → No log alerts
- Only create `type: logs` rules → No metrics alerts
- Alloy will only sync rules that match the selectors

### Q: Can I combine metrics and log conditions in one alert?

**A**: No. Each ruler evaluates its own query language:

- Mimir ruler: PromQL only
- Loki ruler: LogQL only

However, you can:

- Create separate alerts that fire together
- Use AlertManager to correlate them
- Create runbooks that check both

## Troubleshooting

### Rules not syncing

```bash
# Check Alloy-Alerts logs
kubectl logs -n alloy-system -l app=alloy-alerts -f

# Look for sync errors
kubectl logs -n alloy-system -l app=alloy-alerts | grep -i error

# Verify PrometheusRule labels
kubectl get prometheusrules -n monitoring -o yaml | grep -A 5 labels
```

### Alerts not firing

```bash
# Check if data exists
curl -H "X-Scope-OrgID: stage" \
  'http://localhost:9009/prometheus/api/v1/query?query=up'

curl -H "X-Scope-OrgID: stage" \
  'http://localhost:3100/loki/api/v1/query?query={app="myapp"}'

# Check rule evaluation state
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/prometheus/api/v1/rules | \
  jq '.data.groups[].rules[].state'
```

### Alerts not routing correctly

```bash
# Check AlertManager config
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/api/v1/alerts | jq

# Check alert labels
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/alertmanager/api/v2/alerts | \
  jq '.[].labels'
```

## Summary

**One Unified System** powered by:

- **Kubernetes-native**: PrometheusRule CRDs for everything
- **Automatic syncing**: Alloy watches and syncs rules
- **Smart routing**: Right rules go to right rulers
- **Centralized alerting**: One AlertManager for all alerts
- **Multi-tenant**: Complete isolation per tenant

This architecture provides the best of all worlds: simplicity for users (just apply CRDs), but sophisticated routing under the hood for proper evaluation and alerting.
