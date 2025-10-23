# Alerting Stack Summary

## 🎯 Complete Alerting Architecture

Your LGTMO stack now includes a comprehensive alerting solution that works across **Metrics, Logs, and Traces**.

```
┌────────────────────────────────────────────────────────────────┐
│                    OBSERVABILITY SIGNALS                        │
└────────────────────────────────────────────────────────────────┘

┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│    MIMIR     │    │     LOKI     │    │    TEMPO     │
│  (Metrics)   │    │    (Logs)    │    │   (Traces)   │
│              │    │              │    │              │
│  Evaluates   │    │  Evaluates   │    │  Evaluates   │
│  PromQL      │    │  LogQL       │    │  TraceQL     │
│  Rules       │    │  Rules       │    │  Metrics     │
└──────┬───────┘    └──────┬───────┘    └──────┬───────┘
       │                   │                   │
       │    Fires Alerts   │   Fires Alerts    │
       └───────────────────┼───────────────────┘
                           ▼
                  ┌────────────────┐
                  │ ALERTMANAGER   │
                  │                │
                  │ • Deduplicates │
                  │ • Groups       │
                  │ • Routes       │
                  │ • Silences     │
                  │ • Inhibits     │
                  └────────┬───────┘
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
       ┌────────┐     ┌────────┐    ┌──────────┐
       │ Slack  │     │  Email │    │ PagerDuty│
       └────────┘     └────────┘    └──────────┘
```

## 📦 What Was Added

### 1. Alertmanager Component

**Location**: `gitops/components/monitoring/alertmanager/`

**Structure**:

```
alertmanager/
├── base/
│   ├── alertmanager-config.yaml      # Main configuration
│   ├── alertmanager-statefulset.yaml # Deployment
│   ├── alertmanager-service.yaml     # Service
│   └── kustomization.yaml
└── overlays/
    └── monitoring/
        ├── alertmanager-nodeport.yaml # NodePort for dev access
        └── kustomization.yaml
```

**Key Features**:

- Multi-tenant alert routing (tenant-a, tenant-b)
- Source-based routing (mimir, loki, tempo)
- Severity-based routing (critical, warning, info)
- Inhibition rules to prevent alert fatigue
- Ready for Slack, PagerDuty, Email, and Webhook integrations

### 2. Alert Rules

**Location**: `o11y/alerting-rules/base/`

**Files**:

- `metrics-rules.yaml` - 5 metric-based alert rules
- `logs-rules.yaml` - 6 log-based alert rules
- `traces-rules.yaml` - 4 trace-based alert rules

### 3. Updated Configurations

- **Loki**: Updated to point to `http://alertmanager.monitoring.svc.cluster.local:9093`
- **Mimir**: Added ruler configuration to send alerts to Alertmanager

### 4. Helper Script

**Location**: `scripts/load-alert-rules.sh`

Automates loading alert rules into Mimir and Loki ruler APIs.

## 🚀 Quick Start

### Deploy Alertmanager

```bash
kubectl apply -k gitops/components/monitoring/alertmanager/overlays/monitoring/
```

### Deploy Alert Rules

```bash
kubectl apply -f o11y/alerting-rules/base/
```

### Verify Deployment

```bash
# Check Alertmanager pod
kubectl get pods -n monitoring -l app=alertmanager

# Access Alertmanager UI
kubectl port-forward -n monitoring svc/alertmanager 9093:9093
# Open http://localhost:9093
```

### Load Rules (Optional - if using ruler API directly)

```bash
cd scripts
./load-alert-rules.sh
```

## 📊 Alert Types Explained

### ✅ Metrics Alerts (via Mimir)

**What they monitor**: Time-series data

- CPU, memory, disk usage
- Request rates and error rates
- Response times and latencies
- Custom application metrics

**Example Alert**:

```yaml
- alert: HighErrorRate
  expr: |
    (sum by (tenant, service) (rate(http_requests_total{status=~"5.."}[5m])) 
    / 
    sum by (tenant, service) (rate(http_requests_total[5m]))) * 100 > 5
  for: 5m
  labels:
    severity: critical
    source: mimir
```

### ✅ Log Alerts (via Loki)

**What they monitor**: Log patterns and content

- Error log spikes
- Critical/Fatal messages
- Panic/crash patterns
- Authentication failures
- Database errors
- Missing logs (potential downtime)

**Example Alert**:

```yaml
- alert: ApplicationPanic
  expr: |
    sum by (tenant, app) (count_over_time({app=~".+"} |~ "(?i)(panic|fatal|crashed)" [5m])) > 0
  for: 1m
  labels:
    severity: critical
    source: loki
```

### ✅ Trace Alerts (via Tempo)

**What they monitor**: Distributed trace data

- End-to-end latency (P95, P99)
- Service dependency failures
- Slow database queries
- Error rates per service/span

**Example Alert**:

```yaml
- alert: HighTraceLatency
  expr: |
    histogram_quantile(0.95, 
      sum by (tenant, service_name, le) (
        rate(traces_spanmetrics_latency_bucket[5m])
      )
    ) > 1000
  for: 5m
  labels:
    severity: warning
    source: tempo
```

## 🔧 Configuration

### Customize Alertmanager Receivers

Edit `gitops/components/monitoring/alertmanager/base/alertmanager-config.yaml`:

**Add Slack**:

```yaml
receivers:
  - name: "slack-alerts"
    slack_configs:
      - api_url: "https://hooks.slack.com/services/YOUR/WEBHOOK"
        channel: "#alerts"
        title: "{{ .GroupLabels.alertname }}"
```

**Add PagerDuty**:

```yaml
receivers:
  - name: "pagerduty-critical"
    pagerduty_configs:
      - service_key: "YOUR_PAGERDUTY_KEY"
```

**Add Email**:

```yaml
global:
  smtp_smarthost: "smtp.gmail.com:587"
  smtp_from: "alerts@example.com"
  smtp_auth_username: "user@example.com"
  smtp_auth_password: "password"

receivers:
  - name: "email-team"
    email_configs:
      - to: "team@example.com"
```

After editing, redeploy:

```bash
kubectl apply -k gitops/components/monitoring/alertmanager/overlays/monitoring/
```

## 🎨 Alertmanager UI

Access at: `http://localhost:9093` (after port-forward)

**Features**:

- View all active alerts
- Create silences
- See alert grouping
- View alert history
- Manage alert routing

## 🔍 Testing Alerts

### Test Metric Alert

```bash
# Port-forward Mimir
kubectl port-forward -n monitoring svc/mimir 9009:9009

# Send test metrics with high error rate
for i in {1..100}; do
  echo "http_requests_total{status=\"500\",service=\"test\",tenant=\"tenant-a\"} 1" | \
  curl -X POST -H "X-Scope-OrgID: tenant-a" \
    --data-binary @- http://localhost:9009/api/v1/push
done
```

### Test Log Alert

```bash
# Port-forward Loki
kubectl port-forward -n monitoring svc/loki 3100:3100

# Send error logs
for i in {1..50}; do
  curl -X POST http://localhost:3100/loki/api/v1/push \
    -H "Content-Type: application/json" \
    -H "X-Scope-OrgID: tenant-a" \
    -d '{"streams": [{"stream": {"level":"error","app":"test"},"values":[["'$(date +%s%N)'","Test error message"]]}]}'
done
```

### View Alerts

```bash
# Check Alertmanager
curl http://localhost:9093/api/v1/alerts | jq

# Check Mimir alerts
curl -H "X-Scope-OrgID: tenant-a" http://localhost:9009/prometheus/api/v1/alerts | jq

# Check Loki alerts
curl -H "X-Scope-OrgID: tenant-a" http://localhost:3100/loki/api/v1/rules/alerts | jq
```

## 🏷️ Label Strategy

For effective alert routing, use consistent labels:

```yaml
labels:
  # Required
  alertname: "HighErrorRate"
  severity: "critical" # critical, warning, info
  source: "mimir" # mimir, loki, tempo

  # Multi-tenancy
  tenant: "tenant-a" # tenant-a, tenant-b

  # Context
  service: "api-gateway"
  cluster: "prod"
  environment: "production"
```

## 📈 Integration with Grafana

Add Alertmanager as a data source in Grafana:

```yaml
apiVersion: 1
datasources:
  - name: Alertmanager
    type: alertmanager
    access: proxy
    url: http://alertmanager.monitoring.svc.cluster.local:9093
    jsonData:
      implementation: prometheus
```

Then you can:

- View alerts in Grafana dashboards
- Create alert panels
- Manage silences from Grafana UI

## 📚 Documentation

**Detailed Docs**: See `gitops/components/monitoring/alertmanager/README.md`

**Key Topics**:

- Architecture deep-dive
- Configuration examples
- Receiver integrations
- Troubleshooting guide
- Best practices

## 🎓 Key Concepts

### Grouping

Alerts with the same labels are grouped together to reduce notification spam.

- `group_by: ['alertname', 'cluster', 'service', 'tenant']`
- `group_wait: 10s` - Wait 10s for more alerts before sending
- `group_interval: 10s` - Send new alerts for the group every 10s
- `repeat_interval: 12h` - Repeat notifications every 12h

### Inhibition

Suppress lower-severity alerts when higher-severity ones are firing:

```yaml
inhibit_rules:
  - source_matchers:
      - severity="critical"
    target_matchers:
      - severity="warning"
    equal: ["alertname", "service"]
```

### Routing

Route different alert types to different receivers:

```yaml
routes:
  - receiver: "pagerduty"
    matchers:
      - severity="critical"
  - receiver: "slack"
    matchers:
      - severity="warning"
```

## ✅ What You Get

| Signal  | What It Monitors        | Example Alert                |
| ------- | ----------------------- | ---------------------------- |
| Metrics | System & App metrics    | High CPU, Error rates        |
| Logs    | Log patterns & content  | Error spikes, Panic messages |
| Traces  | Request flows & latency | Slow queries, Failed calls   |

**All three feed into a single Alertmanager** for unified alert management!

## 🔗 Next Steps

1. **Configure Receivers**: Add your Slack/PagerDuty/Email configs
2. **Customize Rules**: Adjust thresholds in alert rules
3. **Add More Rules**: Create custom rules for your use cases
4. **Set Up Grafana**: Add Alertmanager as datasource
5. **Test Thoroughly**: Trigger test alerts to verify routing

## 💡 Pro Tips

1. Start with **info** severity, then tune to **warning/critical**
2. Use **`for: 5m`** to avoid alert flapping
3. Add **runbook_url** to annotations for incident response
4. Test alerts regularly (monthly)
5. Review and adjust thresholds based on false positives
6. Use silences during maintenance windows
7. Monitor Alertmanager itself!

---

**Questions?** Check the detailed README or Alertmanager docs!
