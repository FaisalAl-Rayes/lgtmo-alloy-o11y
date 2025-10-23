# Alertmanager Setup

## Overview

Alertmanager handles alerts sent by client applications such as Mimir, Loki, and Tempo. It takes care of deduplicating, grouping, and routing alerts to the correct receiver integrations such as email, PagerDuty, Slack, or custom webhooks.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      LGTMO Stack                             │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────┐     ┌─────────┐     ┌─────────┐               │
│  │  Mimir  │     │  Loki   │     │  Tempo  │               │
│  │ (Metrics)│    │  (Logs) │     │ (Traces)│               │
│  └────┬────┘     └────┬────┘     └────┬────┘               │
│       │               │               │                      │
│       │  Evaluate     │  Evaluate     │  Evaluate           │
│       │  Prometheus   │  LogQL        │  TraceQL            │
│       │  Rules        │  Rules        │  Rules              │
│       │               │               │                      │
│       └───────────────┴───────────────┘                      │
│                       │                                      │
│                       ▼                                      │
│              ┌────────────────┐                              │
│              │  Alertmanager  │                              │
│              │                │                              │
│              │ • Deduplicate  │                              │
│              │ • Group        │                              │
│              │ • Route        │                              │
│              │ • Silence      │                              │
│              │ • Inhibit      │                              │
│              └────────┬───────┘                              │
│                       │                                      │
│                       ▼                                      │
│              ┌────────────────┐                              │
│              │   Receivers    │                              │
│              │                │                              │
│              │ • Slack        │                              │
│              │ • PagerDuty    │                              │
│              │ • Email        │                              │
│              │ • Webhook      │                              │
│              └────────────────┘                              │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## What Alertmanager Works With

### ✅ Metrics (Mimir/Prometheus)

- **Use Case**: System metrics, application metrics, RED metrics (Rate, Errors, Duration)
- **Alert Types**: CPU/Memory usage, disk space, request rates, error rates, SLO violations
- **Rule Format**: PromQL expressions
- **Example**: `rate(http_requests_total{status=~"5.."}[5m]) > 0.05`

### ✅ Logs (Loki)

- **Use Case**: Log patterns, error messages, security events, audit trails
- **Alert Types**: Error log spikes, panic messages, authentication failures, application crashes
- **Rule Format**: LogQL expressions (with Prometheus-compatible ruler API)
- **Example**: `sum(rate({level="error"}[5m])) > 10`

### ✅ Traces (Tempo)

- **Use Case**: Service latency, dependency failures, distributed system health
- **Alert Types**: High latency, failed downstream calls, slow database queries
- **Rule Format**: TraceQL metrics (via span metrics generator)
- **Example**: `histogram_quantile(0.95, traces_spanmetrics_latency_bucket) > 1000`

## Key Features

### 1. Deduplication

Alertmanager automatically deduplicates identical alerts from multiple sources.

### 2. Grouping

Alerts are grouped by labels (`alertname`, `cluster`, `service`, `tenant`) to reduce notification spam.

### 3. Routing

Alerts are routed to different receivers based on:

- **Source**: `mimir`, `loki`, `tempo`
- **Severity**: `critical`, `warning`, `info`
- **Tenant**: `tenant-a`, `tenant-b`

### 4. Inhibition

Lower-severity alerts are suppressed when higher-severity alerts are firing:

- Warning alerts inhibited when critical alerts are active
- All alerts inhibited during maintenance mode

### 5. Silencing

Temporarily mute alerts via the Alertmanager UI or API.

## Configuration

### Alertmanager Config Structure

```yaml
global:
  resolve_timeout: 5m

route:
  receiver: "default"
  group_by: ["alertname", "cluster", "service", "tenant"]
  routes:
    - receiver: "metrics-alerts"
      matchers:
        - source="mimir"
    - receiver: "log-alerts"
      matchers:
        - source="loki"
    - receiver: "trace-alerts"
      matchers:
        - source="tempo"

receivers:
  - name: "default"
  - name: "metrics-alerts"
  - name: "log-alerts"
  - name: "trace-alerts"
```

### Configuring Receivers

#### Slack

```yaml
receivers:
  - name: "slack-alerts"
    slack_configs:
      - api_url: "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
        channel: "#alerts"
        title: "{{ .GroupLabels.alertname }}"
        text: "{{ range .Alerts }}{{ .Annotations.description }}{{ end }}"
```

#### PagerDuty

```yaml
receivers:
  - name: "pagerduty-critical"
    pagerduty_configs:
      - service_key: "YOUR_PAGERDUTY_KEY"
        severity: "{{ .GroupLabels.severity }}"
```

#### Email

```yaml
global:
  smtp_smarthost: "smtp.gmail.com:587"
  smtp_from: "alertmanager@example.com"
  smtp_auth_username: "user@example.com"
  smtp_auth_password: "password"

receivers:
  - name: "email-alerts"
    email_configs:
      - to: "team@example.com"
        headers:
          Subject: "Alert: {{ .GroupLabels.alertname }}"
```

#### Webhook

```yaml
receivers:
  - name: "webhook-alerts"
    webhook_configs:
      - url: "http://your-service:8080/webhook"
        send_resolved: true
```

## Deployment

### 1. Deploy Alertmanager

```bash
kubectl apply -k gitops/components/monitoring/alertmanager/overlays/monitoring/
```

### 2. Verify Deployment

```bash
# Check if Alertmanager is running
kubectl get pods -n monitoring -l app=alertmanager

# Check service
kubectl get svc -n monitoring alertmanager

# Access Alertmanager UI
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
# Open http://localhost:9093
```

### 3. Deploy Alert Rules

```bash
# Deploy rules to Mimir
kubectl apply -f o11y/alerting-rules/base/metrics-rules.yaml

# Deploy rules to Loki
kubectl apply -f o11y/alerting-rules/base/logs-rules.yaml

# Deploy rules to Tempo (if span metrics are enabled)
kubectl apply -f o11y/alerting-rules/base/traces-rules.yaml
```

## Testing Alerts

### Test Metrics Alert

```bash
# Simulate high error rate
for i in {1..1000}; do
  curl -X POST \
    -H "X-Scope-OrgID: tenant-a" \
    http://your-app:8080/error
done
```

### Test Log Alert

```bash
# Generate error logs
kubectl exec -n monitoring deployment/your-app -- \
  sh -c 'for i in {1..100}; do echo "{\"level\":\"error\",\"msg\":\"Test error\"}"; done'
```

### Test Manual Alert (via Alertmanager API)

```bash
curl -X POST http://localhost:9093/api/v1/alerts \
  -H "Content-Type: application/json" \
  -d '[{
    "labels": {
      "alertname": "TestAlert",
      "severity": "warning",
      "source": "manual"
    },
    "annotations": {
      "summary": "This is a test alert"
    }
  }]'
```

## Accessing Alertmanager UI

### Via NodePort (Development)

```bash
# NodePort is configured at 30903
http://<node-ip>:30903
```

### Via Port Forward

```bash
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
# Open http://localhost:9093
```

### Via Ingress (Production)

Add an Ingress resource to expose Alertmanager externally with authentication.

## Integration with Grafana

Alertmanager can be added as a data source in Grafana to:

1. View active alerts
2. Create alert dashboards
3. Manage silences from Grafana UI

Add to Grafana datasources:

```yaml
- name: Alertmanager
  type: alertmanager
  access: proxy
  url: http://alertmanager.monitoring.svc.cluster.local:9093
  jsonData:
    implementation: prometheus
```

## Multi-Tenancy Support

The Alertmanager configuration includes tenant-specific routing:

```yaml
routes:
  - receiver: "tenant-a"
    matchers:
      - tenant="tenant-a"
  - receiver: "tenant-b"
    matchers:
      - tenant="tenant-b"
```

Ensure your alerts include the `tenant` label:

```yaml
labels:
  tenant: "tenant-a"
```

## Best Practices

1. **Label Everything**: Use consistent labels across metrics, logs, and traces

   - `tenant`: For multi-tenancy
   - `service`: Service name
   - `severity`: `critical`, `warning`, `info`
   - `source`: `mimir`, `loki`, `tempo`

2. **Use Inhibition Rules**: Prevent alert fatigue by suppressing redundant alerts

3. **Set Proper Group Intervals**: Balance between notification speed and grouping efficiency

4. **Configure Multiple Receivers**: Route different alert types to appropriate channels

5. **Test Alert Rules**: Regularly test your alert rules to ensure they work as expected

6. **Document Runbooks**: Add runbook links to alert annotations

   ```yaml
   annotations:
     summary: "High error rate"
     runbook_url: "https://wiki.example.com/runbooks/high-error-rate"
   ```

7. **Monitor Alertmanager**: Set up alerts for Alertmanager itself
   ```yaml
   - alert: AlertmanagerDown
     expr: up{job="alertmanager"} == 0
   ```

## Troubleshooting

### Alerts Not Showing Up

1. Check if Mimir/Loki/Tempo are configured with correct Alertmanager URL
2. Verify Alertmanager service is accessible: `kubectl get svc -n monitoring alertmanager`
3. Check Alertmanager logs: `kubectl logs -n monitoring -l app=alertmanager`

### Alerts Not Being Sent to Receivers

1. Verify receiver configuration in alertmanager-config.yaml
2. Check routing rules match your alert labels
3. Look for errors in Alertmanager logs
4. Test receiver connectivity (e.g., Slack webhook)

### Too Many Notifications

1. Adjust `group_interval` and `repeat_interval`
2. Use inhibition rules
3. Review alert thresholds and `for` duration

### Alerts Resolved Too Quickly

1. Increase `for` duration in alert rules
2. Check `resolve_timeout` in Alertmanager config

## Resources

- [Alertmanager Documentation](https://prometheus.io/docs/alerting/latest/alertmanager/)
- [Prometheus Alerting Rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [Loki Alerting](https://grafana.com/docs/loki/latest/alert/)
- [Tempo Metrics Generator](https://grafana.com/docs/tempo/latest/metrics-generator/)
