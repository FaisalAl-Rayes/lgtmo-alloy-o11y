# Multi-Tenant Alerting Flow Diagram

## Complete Data & Alert Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          APPLICATION LAYER                               │
├─────────────────────────────────────────────────────────────────────────┤
│  Apps (stage namespace)          │  Apps (prod namespace)               │
│  - Expose /metrics               │  - Expose /metrics                   │
│  - Send OTLP traces/logs         │  - Send OTLP traces/logs             │
│  - ServiceMonitor CRDs           │  - ServiceMonitor CRDs               │
└──────────────┬───────────────────┴──────────────┬───────────────────────┘
               │                                   │
               │ Scrape                           │ Scrape
               ▼                                   ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           ALLOY LAYER                                    │
├─────────────────────────────────────────────────────────────────────────┤
│  Alloy Metrics                                                           │
│  - prometheus.operator.servicemonitors → scrapes apps                   │
│  - otelcol.receiver.otlp → receives OTLP metrics                        │
│  - mimir.rules.kubernetes "stage_rules" → watches PrometheusRules      │
│  - mimir.rules.kubernetes "prod_rules" → watches PrometheusRules       │
│  - prometheus.remote_write → sends to Mimir with X-Scope-OrgID         │
└──────────────┬───────────────────────────────────┬──────────────────────┘
               │                                    │
               │ Write Metrics                     │ Sync Rules
               │ X-Scope-OrgID: stage/prod         │ Per Tenant
               ▼                                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                           MIMIR LAYER                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────────┐         ┌──────────────────┐                     │
│  │ Mimir Distributor│         │   Mimir Ruler    │                     │
│  │ (Receives Metrics│         │ (Evaluates Rules)│                     │
│  │  per tenant)     │         │                  │                     │
│  └────────┬─────────┘         └────────┬─────────┘                     │
│           │                             │                               │
│           │ Store                       │ Query tenant data             │
│           ▼                             │                               │
│  ┌──────────────────┐                  │                               │
│  │ Mimir Ingester   │                  │                               │
│  │ (Per-tenant      │◄─────────────────┘                               │
│  │  isolation)      │                                                   │
│  └──────────────────┘                                                   │
│           │                                                              │
│           │ Fire Alerts                                                 │
│           ▼                                                              │
│  ┌──────────────────────────────────────────────┐                      │
│  │       Mimir AlertManager                      │                      │
│  │  ┌──────────────┐    ┌──────────────┐       │                      │
│  │  │ Stage Tenant │    │ Prod Tenant  │       │                      │
│  │  │ - Own config │    │ - Own config │       │                      │
│  │  │ - Own routes │    │ - Own routes │       │                      │
│  │  │ - Own UI     │    │ - Own UI     │       │                      │
│  │  └──────┬───────┘    └──────┬───────┘       │                      │
│  └─────────┼────────────────────┼───────────────┘                      │
└────────────┼────────────────────┼────────────────────────────────────┘
             │                    │
             │                    │
             ▼                    ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     NOTIFICATION LAYER                                   │
├─────────────────────────────────────────────────────────────────────────┤
│  Stage Notifications        │  Prod Notifications                       │
│  - Slack #stage-alerts      │  - PagerDuty (critical)                  │
│  - Lower severity           │  - Slack #prod-alerts                     │
│                             │  - Email (optional)                       │
└─────────────────────────────────────────────────────────────────────────┘
```

## PrometheusRule CRD Syncing Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                     KUBERNETES API SERVER                                │
│                                                                          │
│  PrometheusRule CRDs with labels:                                       │
│  ┌──────────────────────┐         ┌──────────────────────┐            │
│  │ app-alerts-stage     │         │ app-alerts-prod      │            │
│  │ labels:              │         │ labels:              │            │
│  │   tenant: stage      │         │   tenant: prod       │            │
│  └──────────────────────┘         └──────────────────────┘            │
└───────────────┬──────────────────────────────┬──────────────────────────┘
                │                               │
                │ Watch                        │ Watch
                │ (label: tenant=stage)        │ (label: tenant=prod)
                │                               │
                ▼                               ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                              ALLOY                                       │
│                                                                          │
│  ┌───────────────────────────┐   ┌───────────────────────────┐        │
│  │ mimir.rules.kubernetes    │   │ mimir.rules.kubernetes    │        │
│  │ "stage_rules"             │   │ "prod_rules"              │        │
│  │                           │   │                           │        │
│  │ tenant_id = "stage"       │   │ tenant_id = "prod"        │        │
│  │ rule_selector:            │   │ rule_selector:            │        │
│  │   tenant = "stage"        │   │   tenant = "prod"         │        │
│  └─────────────┬─────────────┘   └─────────────┬─────────────┘        │
└────────────────┼─────────────────────────────────┼──────────────────────┘
                 │                                 │
                 │ POST rules with                │ POST rules with
                 │ X-Scope-OrgID: stage           │ X-Scope-OrgID: prod
                 │                                 │
                 ▼                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         MIMIR RULER API                                  │
│                                                                          │
│  /prometheus/config/v1/rules                                            │
│                                                                          │
│  ┌──────────────────────┐         ┌──────────────────────┐            │
│  │ Stage Tenant Rules   │         │ Prod Tenant Rules    │            │
│  │ /data/mimir/rules/   │         │ /data/mimir/rules/   │            │
│  │   stage/             │         │   prod/              │            │
│  └──────────────────────┘         └──────────────────────┘            │
│                                                                          │
│  Evaluation happens against tenant-specific metrics                     │
└─────────────────────────────────────────────────────────────────────────┘
```

## Alert Routing in Multi-Tenant AlertManager

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      FIRED ALERTS                                        │
│                                                                          │
│  Alert with labels:                                                     │
│    alertname: HighErrorRate                                             │
│    severity: critical                                                   │
│    tenant: prod                                                         │
│    environment: prod                                                    │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │
                                │ Goes to tenant-specific AlertManager
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│            MIMIR ALERTMANAGER (Tenant: prod)                            │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────┐          │
│  │ Route Configuration                                       │          │
│  │                                                            │          │
│  │ Root Route                                                │          │
│  │  group_by: ['alertname', 'cluster']                      │          │
│  │  receiver: 'prod-default'                                 │          │
│  │                                                            │          │
│  │  Child Routes:                                            │          │
│  │  ┌──────────────────────────────────────────┐           │          │
│  │  │ Match: severity="critical"                │           │          │
│  │  │ Receiver: prod-pagerduty                  │           │          │
│  │  │ Continue: true                            │           │          │
│  │  └──────────────────────────────────────────┘           │          │
│  │                                                            │          │
│  │  ┌──────────────────────────────────────────┐           │          │
│  │  │ Receiver: prod-slack                      │           │          │
│  │  │ (All alerts)                              │           │          │
│  │  └──────────────────────────────────────────┘           │          │
│  └──────────────────────────────────────────────────────────┘          │
│                                                                          │
│  Grouping: Alerts with same 'alertname' and 'cluster' grouped together │
│  Deduplication: Duplicate alerts merged                                │
│  Inhibition: Critical alerts suppress warnings                         │
└──────────────────┬──────────────────────┬──────────────────────────────┘
                   │                      │
                   │                      │
                   ▼                      ▼
        ┌──────────────────┐  ┌──────────────────┐
        │   PagerDuty      │  │      Slack       │
        │  (Critical only) │  │   (All alerts)   │
        └──────────────────┘  └──────────────────┘
```

## Key Concepts

### Tenant Isolation

- **Metrics**: Isolated by `X-Scope-OrgID` header in remote write
- **Rules**: Isolated by tenant ID in Mimir's ruler storage
- **Alerts**: Routed to tenant-specific AlertManager configs
- **UI**: Each tenant has separate AlertManager UI

### Label-Based Routing

PrometheusRule CRDs use the `tenant` label:

```yaml
labels:
  tenant: stage # or prod
```

Alloy matches this label:

```hcl
rule_selector {
  match_labels = {
    tenant = "stage"
  }
}
```

### Multi-Tenant Benefits

1. **Isolation**: Each tenant's data and alerts are separate
2. **Different Policies**: Stage can be lenient, prod strict
3. **Different Notifications**: Stage → Slack, Prod → PagerDuty + Slack
4. **Independent Scaling**: Can tune resources per tenant
5. **Security**: Tenants can't see each other's data

## Example: Alert Lifecycle

```
1. Developer creates PrometheusRule CRD
   ↓
2. Alloy watches Kubernetes API, detects new rule
   ↓
3. Alloy syncs rule to Mimir ruler (with X-Scope-OrgID header)
   ↓
4. Mimir ruler evaluates rule against tenant's metrics
   ↓
5. If threshold exceeded, alert fires
   ↓
6. Alert sent to Mimir AlertManager (tenant-specific)
   ↓
7. AlertManager groups, deduplicates, applies routing
   ↓
8. Notification sent to configured receiver (Slack/PagerDuty/Email)
   ↓
9. On-call engineer receives notification
   ↓
10. Engineer uses runbook URL to resolve issue
```

---

This architecture provides production-grade multi-tenant alerting with:

- ✅ Kubernetes-native resources
- ✅ GitOps friendly
- ✅ Automatic syncing
- ✅ Complete tenant isolation
- ✅ Flexible per-tenant configuration
