# Mimir Multi-Tenant Alerting Guide

This guide explains how to use Mimir's built-in multi-tenant AlertManager with PrometheusRule CRDs and Alloy.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    PrometheusRule CRDs                          │
│           (Kubernetes Native Alert Definitions)                 │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ Watches & Syncs
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                         ALLOY                                    │
│  - mimir.rules.kubernetes (stage_rules)  → Tenant: stage       │
│  - mimir.rules.kubernetes (prod_rules)   → Tenant: prod        │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ Syncs per Tenant
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                      MIMIR RULER                                 │
│  - Evaluates rules per tenant against tenant's metrics          │
│  - Each tenant has isolated rule storage                        │
└─────────────────────────────────────────────────────────────────┘
                            │
                            │ Fires Alerts
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                  MIMIR ALERTMANAGER                             │
│  - Multi-tenant alert routing                                   │
│  - Per-tenant configurations                                    │
│  - Deduplication, grouping, inhibition                          │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
                   ┌────────────────┐
                   │  Notifications │
                   │  Slack/PagerDuty│
                   │  Email/Webhook │
                   └────────────────┘
```

## Components

### 1. Mimir Configuration

**Location**: `gitops/components/monitoring/mimir/base/mimir-config.yaml`

Key configuration sections:

```yaml
ruler:
  enable_api: true
  alertmanager_url: http://localhost:9009/alertmanager # Uses Mimir's built-in AlertManager
  rule_path: /data/mimir/rules-data

alertmanager:
  enable_api: true
  data_dir: /data/mimir/alertmanager
  external_url: http://mimir:9009/alertmanager
  fallback_config_file: /etc/mimir/alertmanager-fallback.yaml

alertmanager_storage:
  backend: filesystem
  filesystem:
    dir: /data/mimir/alertmanager-configs
```

### 2. AlertManager Fallback Configuration

**Location**: `gitops/components/monitoring/mimir/base/alertmanager-fallback-config.yaml`

This is the default configuration used when a tenant doesn't have a custom config. It provides:

- Default routing by severity and tenant
- Inhibition rules to prevent alert fatigue
- Placeholder receivers (webhook, slack, pagerduty)

### 3. Alloy Configuration

**Location**: `gitops/components/alloy-metrics/base/alloy-metrics.yaml`

Alloy watches PrometheusRule CRDs and syncs them to Mimir:

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

## Creating PrometheusRule CRDs

### Stage Environment Rules

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: app-alerts-stage
  namespace: monitoring
  labels:
    tenant: stage # ← CRITICAL: This label determines which tenant
    type: metrics # ← Distinguishes metrics-based from log-based rules
    prometheus: monitoring
spec:
  groups:
    - name: stage.app.alerts
      interval: 30s
      rules:
        - alert: HighErrorRate
          expr: |
            (sum(rate(app_errors_total[5m])) / sum(rate(app_requests_total[5m]))) > 0.05
          for: 2m
          labels:
            severity: warning
            tenant: stage
          annotations:
            summary: "High error rate in stage"
```

### Production Environment Rules

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: app-alerts-prod
  namespace: monitoring
  labels:
    tenant: prod # ← Different tenant
    type: metrics # ← Metrics-based alerting rules
    prometheus: monitoring
spec:
  groups:
    - name: prod.app.alerts
      interval: 30s
      rules:
        - alert: HighErrorRate
          expr: |
            (sum(rate(app_errors_total[5m])) / sum(rate(app_requests_total[5m]))) > 0.02
          for: 5m
          labels:
            severity: critical # Higher severity for prod
            tenant: prod
          annotations:
            summary: "PRODUCTION: High error rate"
            runbook_url: "https://wiki.example.com/runbooks/errors"
```

## Configuring Per-Tenant AlertManager Settings

### Upload Tenant-Specific AlertManager Config

```bash
# Port-forward Mimir
kubectl port-forward -n monitoring svc/mimir 9009:9009

# Configure AlertManager for stage tenant
curl -X POST http://localhost:9009/api/v1/alerts \
  -H "Content-Type: application/yaml" \
  -H "X-Scope-OrgID: stage" \
  --data-binary @- <<'EOF'
global:
  resolve_timeout: 5m
  slack_api_url: 'https://hooks.slack.com/services/YOUR/STAGE/WEBHOOK'

route:
  group_by: ['alertname', 'cluster']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'stage-slack'

receivers:
  - name: 'stage-slack'
    slack_configs:
      - channel: '#stage-alerts'
        title: 'Stage Alert: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}'
EOF

# Configure AlertManager for prod tenant
curl -X POST http://localhost:9009/api/v1/alerts \
  -H "Content-Type: application/yaml" \
  -H "X-Scope-OrgID: prod" \
  --data-binary @- <<'EOF'
global:
  resolve_timeout: 5m
  pagerduty_url: 'https://events.pagerduty.com/v2/enqueue'
  slack_api_url: 'https://hooks.slack.com/services/YOUR/PROD/WEBHOOK'

route:
  group_by: ['alertname', 'cluster']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 4h
  receiver: 'prod-default'

  routes:
    # Critical alerts go to PagerDuty
    - receiver: 'prod-pagerduty'
      matchers:
        - severity="critical"
      continue: true

    # All alerts also go to Slack
    - receiver: 'prod-slack'

receivers:
  - name: 'prod-default'

  - name: 'prod-pagerduty'
    pagerduty_configs:
      - service_key: 'YOUR_PAGERDUTY_INTEGRATION_KEY'
        description: '{{ .GroupLabels.alertname }}'

  - name: 'prod-slack'
    slack_configs:
      - channel: '#prod-alerts'
        title: 'PRODUCTION Alert: {{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}\n{{ end }}'
        color: '{{ if eq .Status "firing" }}danger{{ else }}good{{ end }}'

inhibit_rules:
  - source_matchers:
      - severity="critical"
    target_matchers:
      - severity="warning"
    equal: ['alertname']
EOF
```

## Accessing AlertManager UI

### Port Forward

```bash
kubectl port-forward -n monitoring svc/mimir 9009:9009
```

### Access Per-Tenant UI

You need to add the `X-Scope-OrgID` header to access each tenant's AlertManager UI:

**Using curl:**

```bash
# View stage alerts
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/alertmanager/api/v2/alerts | jq

# View prod alerts
curl -H "X-Scope-OrgID: prod" \
  http://localhost:9009/alertmanager/api/v2/alerts | jq
```

**Using browser with ModHeader extension:**

1. Install ModHeader browser extension
2. Add header: `X-Scope-OrgID: stage` (or `prod`)
3. Navigate to: `http://localhost:9009/alertmanager`

## Verification Commands

### Check if Rules are Synced

```bash
# Check stage tenant rules
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/prometheus/api/v1/rules | jq '.data.groups[].rules[].alert'

# Check prod tenant rules
curl -H "X-Scope-OrgID: prod" \
  http://localhost:9009/prometheus/api/v1/rules | jq '.data.groups[].rules[].alert'
```

### Check Active Alerts

```bash
# Check stage alerts
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/prometheus/api/v1/alerts | jq

# Check prod alerts
curl -H "X-Scope-OrgID: prod" \
  http://localhost:9009/prometheus/api/v1/alerts | jq
```

### View AlertManager Configuration

```bash
# Get stage AlertManager config
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/api/v1/alerts | jq

# Get prod AlertManager config
curl -H "X-Scope-OrgID: prod" \
  http://localhost:9009/api/v1/alerts | jq
```

## Testing Alerts

### Trigger a Test Alert

```bash
# Send high error rate metrics to stage tenant
for i in {1..100}; do
  echo "http_requests_total{status=\"500\",service=\"test\",environment=\"stage\"} 1" | \
    curl -X POST -H "X-Scope-OrgID: stage" \
      --data-binary @- http://localhost:9009/api/v1/push
done

# Wait for alert to fire (2-5 minutes depending on rule configuration)
# Then check alerts
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/prometheus/api/v1/alerts | jq
```

## Troubleshooting

### Rules Not Appearing

1. **Check PrometheusRule CRD labels**: Ensure `tenant` label matches Alloy configuration

   ```bash
   kubectl get prometheusrules -n monitoring -o yaml
   ```

2. **Check Alloy logs**: See if rules are being synced

   ```bash
   kubectl logs -n alloy-system -l app=alloy-metrics -f
   ```

3. **Check Mimir ruler API**: Verify rules are loaded
   ```bash
   curl -H "X-Scope-OrgID: stage" \
     http://localhost:9009/prometheus/api/v1/rules | jq
   ```

### Alerts Not Firing

1. **Check if rule expression matches data**: Use Grafana Explore
2. **Verify metrics exist**: Query Mimir directly
3. **Check evaluation time**: Rules have a `for` clause that delays firing

### AlertManager Not Receiving Alerts

1. **Check Mimir ruler config**: Ensure `alertmanager_url` is correct
2. **Check Mimir logs**: Look for AlertManager connection errors
   ```bash
   kubectl logs -n monitoring -l app=mimir -f | grep -i alert
   ```

## Best Practices

1. **Use meaningful alert names**: `HighErrorRate`, `ServiceDown`
2. **Include context in annotations**: Actual values, affected resources
3. **Add runbook URLs**: Link to incident response documentation
4. **Set appropriate thresholds**:
   - Stage: More lenient (for testing)
   - Prod: Stricter (for reliability)
5. **Use inhibition rules**: Prevent alert fatigue
6. **Test alerts regularly**: Verify notification channels work
7. **Monitor your monitoring**: Alert on Mimir/Alloy failures

## Adding New Tenants

1. **Create PrometheusRule CRDs** with new tenant label
2. **Update Alloy configuration**: Add new `mimir.rules.kubernetes` block
3. **Configure AlertManager**: Upload tenant-specific config
4. **Update Grafana datasources**: Add data source for new tenant

## Security Considerations

- **RBAC**: Ensure proper Kubernetes RBAC for PrometheusRule CRDs
- **Network policies**: Restrict access to Mimir API
- **Secrets**: Store sensitive values (API keys, passwords) in Kubernetes Secrets
- **Tenant isolation**: Each tenant can only access their own alerts and configs

## Additional Resources

- [Mimir AlertManager Documentation](https://grafana.com/docs/mimir/latest/references/architecture/components/alertmanager/)
- [Alloy mimir.rules.kubernetes](https://grafana.com/docs/alloy/latest/reference/components/mimir.rules.kubernetes/)
- [PrometheusRule CRD Spec](https://prometheus-operator.dev/docs/operator/api/#monitoring.coreos.com/v1.PrometheusRule)
