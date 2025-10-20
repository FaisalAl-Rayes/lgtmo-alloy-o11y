# Alloy Alerts Component

This component is responsible for syncing PrometheusRule CRDs to Mimir's multi-tenant ruler.

## Purpose

The `alloy-alerts` component:

- ✅ Watches PrometheusRule CRDs in Kubernetes
- ✅ Syncs rules to Mimir's ruler API per tenant
- ✅ Maintains separation from metrics collection
- ✅ Provides dedicated alert rule management

## Architecture

```
PrometheusRule CRDs (K8s)
         ↓
    Alloy-Alerts
         ↓
  Mimir Ruler (per tenant)
```

## Configuration

### Environment Variables

- `MIMIR_ENDPOINT`: Mimir service endpoint (e.g., `mimir.monitoring.svc.cluster.local:9009`)
- `LOKI_ENDPOINT`: Loki service endpoint (optional, for future log alerting)

### Label Selectors

The component watches PrometheusRule CRDs with specific labels:

**Stage Tenant:**

```yaml
metadata:
  labels:
    tenant: stage
```

**Prod Tenant:**

```yaml
metadata:
  labels:
    tenant: prod
```

## Deployment

### Base Deployment

```bash
kubectl apply -k gitops/components/alloy-alerts/base/
```

### With Overlays

```bash
kubectl apply -k gitops/components/alloy-alerts/overlays/<overlay-name>/
```

## Adding New Tenants

To add a new tenant, edit `alloy-alerts.yaml` and add:

```hcl
mimir.rules.kubernetes "<tenant>_rules" {
  address   = "http://" + env("MIMIR_ENDPOINT")
  tenant_id = "<tenant>"

  rule_selector {
    match_labels = {
      tenant = "<tenant>"
    }
  }

  rule_namespace_selector {
    match_labels = {
      "kubernetes.io/metadata.name" = "monitoring"
    }
  }
}
```

## Verification

Check if Alloy-Alerts is running:

```bash
# Check pod status
kubectl get pods -n alloy-system -l app=alloy-alerts

# Check logs
kubectl logs -n alloy-system -l app=alloy-alerts -f

# Look for rule syncing logs
kubectl logs -n alloy-system -l app=alloy-alerts | grep -i "mimir.rules"
```

Verify rules are synced to Mimir:

```bash
# Port-forward Mimir
kubectl port-forward -n monitoring svc/mimir 9009:9009

# Check stage rules
curl -H "X-Scope-OrgID: stage" \
  http://localhost:9009/prometheus/api/v1/rules | jq

# Check prod rules
curl -H "X-Scope-OrgID: prod" \
  http://localhost:9009/prometheus/api/v1/rules | jq
```

## Comparison with alloy-metrics

| Component         | Purpose            | What it Does                                                      |
| ----------------- | ------------------ | ----------------------------------------------------------------- |
| **alloy-metrics** | Metrics Collection | Scrapes ServiceMonitors, receives OTLP metrics, forwards to Mimir |
| **alloy-alerts**  | Alert Management   | Watches PrometheusRule CRDs, syncs to Mimir ruler per tenant      |
| **alloy-logs**    | Log Collection     | Collects pod logs, receives OTLP logs, forwards to Loki           |
| **alloy-traces**  | Trace Collection   | Receives OTLP traces, forwards to Tempo                           |

## Resource Requirements

This component is lightweight since it only syncs rules (not processing metrics):

- **CPU**: 50m request, 200m limit
- **Memory**: 64Mi request, 256Mi limit
- **Replicas**: 1 (can be increased for HA)

## Self-Monitoring

The component exports its own metrics to Mimir under the `monitoring` tenant:

```promql
# Check if alloy-alerts is up
up{job="alloy-alerts"}

# Check rule sync operations
alloy_mimir_rules_kubernetes_syncs_total
```

## Troubleshooting

### Rules not appearing in Mimir

1. Check Alloy-Alerts logs:

   ```bash
   kubectl logs -n alloy-system -l app=alloy-alerts -f
   ```

2. Verify PrometheusRule CRD has correct labels:

   ```bash
   kubectl get prometheusrules -n monitoring -o yaml | grep -A 5 "labels:"
   ```

3. Check Mimir ruler API:
   ```bash
   curl -H "X-Scope-OrgID: stage" http://localhost:9009/prometheus/api/v1/rules
   ```

### Connection issues to Mimir

1. Verify MIMIR_ENDPOINT environment variable
2. Check network connectivity:
   ```bash
   kubectl exec -n alloy-system -it <alloy-alerts-pod> -- wget -O- http://mimir.monitoring.svc.cluster.local:9009/ready
   ```

### RBAC issues

Ensure Alloy has permissions to watch PrometheusRule CRDs:

```bash
kubectl auth can-i list prometheusrules.monitoring.coreos.com --as=system:serviceaccount:alloy-system:alloy-alerts
```

## Future Enhancements

- [ ] Add Loki rules syncing when available
- [ ] Support multiple namespaces for rule watching
- [ ] Add Grafana dashboard for alert rule inventory
- [ ] Implement rule validation before syncing
- [ ] Add metrics for rule sync success/failure rates
