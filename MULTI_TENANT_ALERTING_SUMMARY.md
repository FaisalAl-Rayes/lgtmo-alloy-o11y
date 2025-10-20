# Multi-Tenant Alerting Implementation Summary

## 🎯 What Was Implemented

A complete multi-tenant alerting solution using:

- **Mimir's built-in multi-tenant AlertManager**
- **Alloy's PrometheusRule CRD syncing**
- **Per-tenant alert rules using Kubernetes native resources**

## 📦 Changes Made

### 1. Mimir Configuration Updates

**File**: `gitops/components/monitoring/mimir/base/mimir-config.yaml`

✅ Enabled Mimir's built-in multi-tenant AlertManager
✅ Configured ruler to use internal AlertManager
✅ Added AlertManager storage configuration

**Key Changes**:

```yaml
ruler:
  alertmanager_url: http://localhost:9009/alertmanager # Changed from external to internal

alertmanager:
  enable_api: true
  data_dir: /data/mimir/alertmanager
  fallback_config_file: /etc/mimir/alertmanager-fallback.yaml

alertmanager_storage:
  backend: filesystem
  filesystem:
    dir: /data/mimir/alertmanager-configs
```

### 2. AlertManager Fallback Configuration

**File**: `gitops/components/monitoring/mimir/base/alertmanager-fallback-config.yaml` (NEW)

✅ Created default AlertManager configuration
✅ Configured routing by severity and tenant
✅ Added inhibition rules
✅ Included placeholder receivers (Slack, PagerDuty, Email)

### 3. Mimir StatefulSet Updates

**File**: `gitops/components/monitoring/mimir/base/mimir-statefulset.yaml`

✅ Added volume mount for AlertManager fallback config
✅ Configured ConfigMap volume for fallback config

### 4. Mimir Kustomization

**File**: `gitops/components/monitoring/mimir/base/kustomization.yaml`

✅ Added alertmanager-fallback-config.yaml to resources

### 5. New Alloy Alerts Component

**Files**:

- `gitops/components/alloy-alerts/base/alloy-alerts.yaml` (NEW)
- `gitops/components/alloy-alerts/overlays/*/` (NEW)

✅ Created dedicated component for alert rule management
✅ Added `mimir.rules.kubernetes` component for stage tenant
✅ Added `mimir.rules.kubernetes` component for prod tenant
✅ Configured label selectors for automatic PrometheusRule syncing
✅ Separated alert management from metrics collection

**Key Configuration**:

```hcl
mimir.rules.kubernetes "stage_rules" {
  address   = "http://" + env("MIMIR_ENDPOINT")
  tenant_id = "stage"
  rule_selector {
    match_labels = {
      tenant = "stage"
    }
  }
}

mimir.rules.kubernetes "prod_rules" {
  address   = "http://" + env("MIMIR_ENDPOINT")
  tenant_id = "prod"
  rule_selector {
    match_labels = {
      tenant = "prod"
    }
  }
}
```

**Why Separate Component?**

- ✅ Separation of concerns (metrics vs alerts)
- ✅ Independent scaling
- ✅ Clearer architecture
- ✅ Isolated failures don't affect metrics collection

### 6. Example PrometheusRule CRDs

**Files**:

- `o11y/alerting-rules/tenants/stage/app-alerts-stage.yaml` (NEW)
- `o11y/alerting-rules/tenants/prod/app-alerts-prod.yaml` (NEW)

✅ Created example alert rules for stage environment
✅ Created example alert rules for prod environment
✅ Different thresholds and severity levels per environment

### 7. Documentation

**Files**:

- `o11y/alerting-rules/tenants/README.md` (NEW)
- `gitops/components/monitoring/mimir/MULTI_TENANT_ALERTING.md` (NEW)

✅ Comprehensive guide on using multi-tenant alerting
✅ Examples for creating PrometheusRule CRDs
✅ Instructions for configuring per-tenant AlertManager
✅ Troubleshooting guide
✅ Best practices

## 🚀 How to Deploy

### Step 1: Deploy Updated Mimir Configuration

```bash
kubectl apply -k gitops/components/monitoring/mimir/overlays/monitoring/
```

### Step 2: Deploy New Alloy Alerts Component

```bash
kubectl apply -k gitops/components/alloy-alerts/overlays/monitoring/
```

This new component is dedicated to managing alert rules.

### Step 3: Deploy Example Alert Rules

```bash
# Deploy stage alerts
kubectl apply -f o11y/alerting-rules/tenants/stage/

# Deploy prod alerts
kubectl apply -f o11y/alerting-rules/tenants/prod/
```

### Step 4: Configure Per-Tenant AlertManager

```bash
# Port-forward Mimir
kubectl port-forward -n monitoring svc/mimir 9009:9009

# Configure stage tenant (example with Slack)
curl -X POST http://localhost:9009/api/v1/alerts \
  -H "Content-Type: application/yaml" \
  -H "X-Scope-OrgID: stage" \
  --data-binary @your-stage-alertmanager-config.yaml

# Configure prod tenant (example with PagerDuty)
curl -X POST http://localhost:9009/api/v1/alerts \
  -H "Content-Type: application/yaml" \
  -H "X-Scope-OrgID: prod" \
  --data-binary @your-prod-alertmanager-config.yaml
```

## ✅ Verification

### Check if Mimir is Running with AlertManager

```bash
kubectl get pods -n monitoring -l app=mimir
kubectl logs -n monitoring -l app=mimir | grep -i alertmanager
```

### Check if Alloy-Alerts is Syncing Rules

```bash
# Check if alloy-alerts pod is running
kubectl get pods -n alloy-system -l app=alloy-alerts

# Check logs for rule syncing
kubectl logs -n alloy-system -l app=alloy-alerts -f | grep -i "mimir.rules"
```

### Verify Rules are Loaded

```bash
# Port-forward Mimir
kubectl port-forward -n monitoring svc/mimir 9009:9009

# Check stage tenant rules
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/prometheus/api/v1/rules | jq '.data.groups[].rules[].alert'

# Check prod tenant rules
curl -H "X-Scope-OrgID: prod" \
  http://localhost:9009/prometheus/api/v1/rules | jq '.data.groups[].rules[].alert'
```

### Check Active Alerts

```bash
# Stage alerts
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/prometheus/api/v1/alerts | jq

# Prod alerts
curl -H "X-Scope-OrgID: prod" \
  http://localhost:9009/prometheus/api/v1/alerts | jq
```

## 🎨 Architecture

```
PrometheusRule CRDs (K8s Native)
         ↓
  Alloy-Alerts (Watches & Syncs)
         ↓
  Mimir Ruler (Evaluates per Tenant)
         ↓
  Mimir AlertManager (Multi-Tenant)
         ↓
  Notifications (Slack/PagerDuty/Email)
```

**Component Separation:**

- `alloy-metrics`: Scrapes and forwards metrics only
- `alloy-alerts`: Manages alert rules syncing only
- `alloy-logs`: Collects and forwards logs only
- `alloy-traces`: Collects and forwards traces only

## 🔑 Key Benefits

1. ✅ **Native Kubernetes Resources**: Use PrometheusRule CRDs
2. ✅ **Multi-Tenant Isolation**: Each tenant has separate rules and alert configs
3. ✅ **Automatic Syncing**: Alloy watches and syncs rules automatically
4. ✅ **No Manual API Calls**: Rules sync via Kubernetes reconciliation
5. ✅ **Different Thresholds**: Stage vs Prod can have different alert criteria
6. ✅ **Per-Tenant AlertManager UI**: Each tenant gets their own UI and config
7. ✅ **GitOps Friendly**: All configuration in Git

## 📊 Example Differences: Stage vs Prod

| Aspect               | Stage      | Prod              |
| -------------------- | ---------- | ----------------- |
| Error Rate Threshold | 5%         | 2%                |
| Evaluation Time      | 2 minutes  | 5 minutes         |
| Severity             | warning    | critical          |
| Runbook URLs         | Optional   | Required          |
| Notifications        | Slack only | PagerDuty + Slack |

## 🔧 Customization

### Adding a New Tenant

1. Create PrometheusRule CRD with `tenant: <new-tenant>` label
2. Add `mimir.rules.kubernetes` block in `alloy-alerts.yaml` for new tenant
3. Configure AlertManager for new tenant via API
4. Update Grafana datasources

**Example: Adding "dev" tenant**

```hcl
// In alloy-alerts.yaml
mimir.rules.kubernetes "dev_rules" {
  address   = "http://" + env("MIMIR_ENDPOINT")
  tenant_id = "dev"
  rule_selector {
    match_labels = {
      tenant = "dev"
    }
  }
  rule_namespace_selector {
    match_labels = {
      "kubernetes.io/metadata.name" = "monitoring"
    }
  }
}
```

### Configuring Receivers

Edit the fallback config or upload tenant-specific configs with your receiver details:

- Slack: Add `slack_configs` with webhook URL
- PagerDuty: Add `pagerduty_configs` with service key
- Email: Configure SMTP settings
- Webhooks: Add `webhook_configs` with endpoint URL

## 📚 Documentation

- **Main Guide**: `gitops/components/monitoring/mimir/MULTI_TENANT_ALERTING.md`
- **Tenant Rules Guide**: `o11y/alerting-rules/tenants/README.md`
- **Example Stage Rules**: `o11y/alerting-rules/tenants/stage/app-alerts-stage.yaml`
- **Example Prod Rules**: `o11y/alerting-rules/tenants/prod/app-alerts-prod.yaml`

## 🎓 Next Steps

1. **Customize AlertManager Receivers**: Add your Slack/PagerDuty/Email configs
2. **Create Custom Alert Rules**: Add rules specific to your applications
3. **Test Alerts**: Trigger test alerts to verify routing works
4. **Monitor the Monitoring**: Set up alerts for Mimir/Alloy health
5. **Document Runbooks**: Add runbook URLs to production alerts

## 🆘 Troubleshooting

See the detailed troubleshooting section in:
`gitops/components/monitoring/mimir/MULTI_TENANT_ALERTING.md`

Common issues:

- Rules not syncing → Check Alloy logs and PrometheusRule labels
- Alerts not firing → Verify metric data exists and rule expressions
- Notifications not sent → Check AlertManager config and receiver setup

---

**You now have a production-ready multi-tenant alerting system! 🎉**
