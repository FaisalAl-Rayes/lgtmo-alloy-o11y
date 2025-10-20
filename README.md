# Multi-Cluster Observability Stack with Grafana Alloy

A complete multi-cluster observability solution using **Grafana Alloy**, **Prometheus Operator**, and the **LGTM+O stack** (Loki, Grafana, Tempo, Mimir, OpenTelemetry) deployed across multiple Kubernetes clusters with GitOps using ArgoCD.

## Architecture

This setup simulates a production-like multi-cluster environment using minikube:

```
┌─────────────────────┐
│  control-cluster    │
│  (ArgoCD)           │
└──────────┬──────────┘
           │ GitOps manages
           ├──────────┬──────────┬─────────────┐
           ▼          ▼          ▼             ▼
┌──────────────┐ ┌──────────┐ ┌──────────┐ ┌────────────────────┐
│stage-cluster │ │prod-     │ │monitoring│ │monitoring-cluster  │
│              │ │cluster   │ │-cluster  │ │                    │
│• Apps        │ │          │ │          │ │• Grafana           │
│• Alloy Agent │ │• Apps    │ │          │ │• Mimir (stage/prod)│
│              │ │• Alloy   │ │          │ │• Loki (stage/prod) │
└──────┬───────┘ └────┬─────┘ │          │ │• Tempo (stage/prod)│
       │              │        │          │ │• PrometheusRules   │
       │   NodePort   │        │          │ │• Prometheus Operator│
       └──────────────┴────────┴──────────┤ └────────────────────┘
                  remote_write/push       │
```

### Clusters

- **control-cluster**: Runs ArgoCD for GitOps deployment management
- **stage-cluster**: Runs stage environment applications
- **prod-cluster**: Runs production environment applications
- **monitoring-cluster**: Centralized monitoring stack with separate instances for stage and prod

### Components

#### Member Clusters (stage/prod)

- **Grafana Alloy Agent**: DaemonSet collecting logs, metrics, and traces from applications
- **Instrumented Applications**: Python Flask apps with OpenTelemetry instrumentation
- **Alloy Operator**: Manages Grafana Alloy agent lifecycle

#### Monitoring Cluster

- **Mimir** (2 instances): Prometheus-compatible metrics storage for stage and prod
- **Loki** (2 instances): Log aggregation for stage and prod
- **Tempo** (2 instances): Distributed tracing backend for stage and prod
- **Grafana**: Unified visualization with datasources for both environments
- **Prometheus Operator**: Provides PrometheusRule CRD for alerting

## Quick Start

### Prerequisites

- Docker and Docker Compose installed
- minikube installed
- kubectl installed
- argocd CLI installed
- At least 12GB of available RAM
- Git repository for GitOps (GitHub, GitLab, etc.)

### 1. Start the Clusters

```bash
./.hack/clusters-up.sh
```

This will:

- Create 4 minikube clusters
- Install ArgoCD in control-cluster
- Register all clusters with ArgoCD
- Configure cross-cluster networking

The script will pause for confirmation after setting up port-forwarding for ArgoCD.

### 2. Get Cluster Information

```bash
./scripts/get-cluster-info.sh
```

This displays:

- Cluster IPs
- Service URLs (Grafana, Apps, etc.)
- Cluster status

### 3. Update Git Repository URL

Before deploying, update the `repoURL` field in all ArgoCD ApplicationSet files to point to your Git repository:

```bash
find gitops/argocd-apps -name "*.yaml" -exec sed -i 's|https://github.com/YOUR_USERNAME/YOUR_REPO.git|YOUR_GIT_REPO_URL|g' {} \;
```

### 4. Update Alloy Endpoints

The Alloy agents need the monitoring cluster's IP to send telemetry data:

```bash
./scripts/update-alloy-endpoints.sh
```

Commit and push these changes to your Git repository.

### 5. Deploy the Stack

Deploy in the following order:

```bash
# Switch to control cluster
kubectl config use-context control-cluster

# Deploy operators
kubectl apply -f gitops/argocd-apps/operators-appset.yaml

# Wait for operators to be ready (2-3 minutes)
kubectl wait --for=condition=available --timeout=300s deployment -l app.kubernetes.io/name=alloy-operator -n alloy-system --context stage-cluster
kubectl wait --for=condition=available --timeout=300s deployment -l app.kubernetes.io/name=alloy-operator -n alloy-system --context prod-cluster

# Deploy monitoring stack
kubectl apply -f gitops/argocd-apps/monitoring-stack-appset.yaml

# Wait for monitoring stack to be ready (3-5 minutes)
kubectl wait --for=condition=ready --timeout=600s pod -l app=mimir -n monitoring --context monitoring-cluster --all
kubectl wait --for=condition=ready --timeout=600s pod -l app=loki -n monitoring --context monitoring-cluster --all
kubectl wait --for=condition=ready --timeout=600s pod -l app=tempo -n monitoring --context monitoring-cluster --all
kubectl wait --for=condition=ready --timeout=600s pod -l app=grafana -n monitoring --context monitoring-cluster --all

# Deploy Alloy agents
kubectl apply -f gitops/argocd-apps/alloy-agents-appset.yaml

# Deploy instrumented applications
kubectl apply -f gitops/argocd-apps/instrumented-apps-appset.yaml

# Deploy alerting rules
kubectl apply -f gitops/argocd-apps/alerting-rules-app.yaml
```

### 6. Access Grafana

Using NodePort:

```bash
# Get monitoring cluster IP
MONITORING_IP=$(minikube ip -p monitoring-cluster)
echo "Grafana: http://$MONITORING_IP:30300"
```

Or use port-forwarding:

```bash
./scripts/port-forward-grafana.sh
# Access at http://localhost:3000
```

### 7. Generate Traffic

Generate traffic to the instrumented applications:

```bash
./scripts/generate-traffic.sh
```

This will continuously send requests to both stage and prod applications, generating logs, metrics, and traces.

## Accessing Services

### Via Ingress (Recommended)

First, set up the Ingress host entries:

```bash
./scripts/setup-ingress-hosts.sh
```

This script will add the necessary entries to your `/etc/hosts` file (requires sudo).

Once configured, you can access services via friendly URLs:

- **Grafana**: http://grafana.monitoring.local
- **Stage App**: http://app.stage.local
- **Prod App**: http://app.prod.local

### Via NodePort

```bash
# Get cluster IPs
STAGE_IP=$(minikube ip -p stage-cluster)
PROD_IP=$(minikube ip -p prod-cluster)
MONITORING_IP=$(minikube ip -p monitoring-cluster)

# Access services
echo "Grafana:     http://$MONITORING_IP:30300"
echo "Stage App:   http://$STAGE_IP:30800"
echo "Prod App:    http://$PROD_IP:30800"
```

### Via Port-Forwarding

```bash
# Grafana
kubectl port-forward -n monitoring service/grafana 3000:3000 --context monitoring-cluster

# Stage App
kubectl port-forward -n apps-stage service/instrumented-app 8080:8080 --context stage-cluster

# Prod App
kubectl port-forward -n apps-prod service/instrumented-app 8081:8080 --context prod-cluster
```

## Using Grafana

Once you access Grafana, you'll see datasources for both stage and prod environments:

### Datasources

- **Mimir-Stage** / **Mimir-Prod**: Metrics (Prometheus-compatible)
- **Loki-Stage** / **Loki-Prod**: Logs
- **Tempo-Stage** / **Tempo-Prod**: Traces

### Exploring Data

1. **View Metrics**:

   - Navigate to Explore
   - Select `Mimir-Stage` or `Mimir-Prod`
   - Try queries like:
     - `app_requests_total` - Total requests
     - `rate(app_requests_total[5m])` - Request rate
     - `app_errors_total` - Error count

2. **View Logs**:

   - Navigate to Explore
   - Select `Loki-Stage` or `Loki-Prod`
   - Try queries like:
     - `{app="instrumented-app"}` - All app logs
     - `{app="instrumented-app"} |= "error"` - Error logs

3. **View Traces**:

   - Navigate to Explore
   - Select `Tempo-Stage` or `Tempo-Prod`
   - Search by service name: `instrumented-app-stage` or `instrumented-app-prod`

4. **Correlate Data**:
   - Click on trace IDs in logs to jump to traces
   - Use the trace-to-logs feature to see related log lines
   - View metrics and traces together for complete observability

## Application Endpoints

The instrumented applications provide several endpoints:

```bash
# Health check
curl http://$STAGE_IP:30800/health

# Generate normal traffic
curl http://$STAGE_IP:30800/
curl http://$STAGE_IP:30800/api/users
curl http://$STAGE_IP:30800/api/data

# Generate slow requests
curl http://$STAGE_IP:30800/api/slow

# Generate errors
curl http://$STAGE_IP:30800/api/error
```

## Alerting

PrometheusRule CRDs are deployed to the monitoring cluster for alerting on:

- High error rates (>5% for 2 minutes)
- High latency (95th percentile >1s for 3 minutes)
- Frequent pod restarts
- Low request rates (potential service issues)
- Service down alerts

View alerts in Grafana under Alerting or by querying Prometheus/Mimir.

## Monitoring Architecture

### Data Flow

1. **Applications** → Send OTLP data to local **Alloy Agent** (via ClusterIP service)
2. **Alloy Agent** → Forwards data to **Monitoring Cluster** backends (via NodePort):
   - Metrics → Mimir (stage: 30090, prod: 30091)
   - Logs → Loki (stage: 30100, prod: 30101)
   - Traces → Tempo (stage: 30200, prod: 30201)
3. **Grafana** → Queries all backends using internal ClusterIP services
4. **PrometheusRules** → Evaluated by Prometheus Operator in monitoring cluster

### Storage

Each monitoring backend uses PersistentVolumeClaims with 10Gi storage:

- Separate instances for stage and prod ensure data isolation
- Configured with filesystem storage for simplicity (can be upgraded to object storage)

## Troubleshooting

### Check Cluster Status

```bash
./scripts/get-cluster-info.sh
```

### Check Pod Status

```bash
# Alloy agents
kubectl get pods -n alloy-system --context stage-cluster
kubectl get pods -n alloy-system --context prod-cluster

# Monitoring stack
kubectl get pods -n monitoring --context monitoring-cluster

# Applications
kubectl get pods -n apps-stage --context stage-cluster
kubectl get pods -n apps-prod --context prod-cluster
```

### Check Logs

```bash
# Alloy agent logs
kubectl logs -n alloy-system -l app=alloy-agent --context stage-cluster -f

# Application logs
kubectl logs -n apps-stage -l app=instrumented-app --context stage-cluster -f

# Mimir logs
kubectl logs -n monitoring -l app=mimir -l environment=stage --context monitoring-cluster -f
```

### Check Alloy Configuration

```bash
# View Alloy config
kubectl get configmap -n alloy-system alloy-config -o yaml --context stage-cluster
```

### Verify Data Flow

```bash
# Check if Mimir is receiving data
MONITORING_IP=$(minikube ip -p monitoring-cluster)
curl http://$MONITORING_IP:30090/api/v1/query?query=up

# Check if Loki is receiving data
curl http://$MONITORING_IP:30100/loki/api/v1/label/__name__/values
```

### ArgoCD UI

Access ArgoCD UI to view application sync status:

```bash
# Port-forward ArgoCD
kubectl port-forward service/argocd-server -n argocd 9797:443 --context control-cluster

# Get admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" --context control-cluster | base64 -d
```

Access at: https://localhost:9797

## Cleanup

To tear down all clusters:

```bash
./.hack/clusters-down.sh
```

This will delete all 4 minikube clusters and their data.

## Directory Structure

```
.
├── .hack/                          # Cluster management scripts
│   ├── clusters-up.sh              # Start all clusters
│   └── clusters-down.sh            # Stop all clusters
├── docker/                         # Docker configurations
│   ├── instrumented-app/           # Instrumented application code
│   │   ├── app.py
│   │   ├── Dockerfile
│   │   └── requirements.txt
│   └── demo-app/                   # Original demo application
├── gitops/                         # GitOps manifests
│   ├── operators/                  # Operator installations
│   │   ├── alloy-operator/         # Grafana Alloy Operator
│   │   │   ├── base/
│   │   │   └── overlays/
│   │   │       ├── stage/
│   │   │       └── prod/
│   │   └── prometheus-operator/    # Prometheus Operator
│   │       ├── base/
│   │       └── overlays/
│   │           └── monitoring/
│   ├── components/                 # Application components
│   │   ├── alloy-agent/            # Alloy agent DaemonSets
│   │   │   ├── base/
│   │   │   └── overlays/
│   │   │       ├── stage/
│   │   │       └── prod/
│   │   ├── instrumented-app/       # Instrumented applications
│   │   │   ├── base/
│   │   │   └── overlays/
│   │   │       ├── stage/
│   │   │       └── prod/
│   │   ├── alerting-rules/         # PrometheusRule CRDs
│   │   │   └── base/
│   │   └── monitoring/             # Monitoring stack
│   │       ├── mimir/
│   │       │   ├── base/
│   │       │   └── overlays/
│   │       │       ├── stage/
│   │       │       └── prod/
│   │       ├── loki/
│   │       │   ├── base/
│   │       │   └── overlays/
│   │       │       ├── stage/
│   │       │       └── prod/
│   │       ├── tempo/
│   │       │   ├── base/
│   │       │   └── overlays/
│   │       │       ├── stage/
│   │       │       └── prod/
│   │       └── grafana/
│   │           ├── base/
│   │           └── overlays/
│   │               └── monitoring/
│   └── argocd-apps/                # ArgoCD Applications
│       ├── operators-appset.yaml
│       ├── alloy-agents-appset.yaml
│       ├── monitoring-stack-appset.yaml
│       ├── instrumented-apps-appset.yaml
│       └── alerting-rules-app.yaml
└── scripts/                        # Helper scripts
    ├── get-cluster-info.sh         # Display cluster information
    ├── setup-ingress-hosts.sh      # Setup /etc/hosts for Ingress access
    ├── port-forward-grafana.sh     # Port-forward Grafana
    ├── generate-traffic.sh         # Generate application traffic
    └── update-alloy-endpoints.sh   # Update Alloy configurations
```

## Key Features

### Multi-Tenancy

- Separate Mimir, Loki, and Tempo instances for stage and prod
- Environment-specific namespaces and labels
- Isolated data storage with separate PVCs

### GitOps with ArgoCD

- Declarative infrastructure management
- Automated sync with Git repository
- ApplicationSets for managing multiple similar deployments
- Self-healing and automated pruning

### Observability

- Full OpenTelemetry instrumentation (logs, metrics, traces)
- Correlation between signals via trace IDs
- Grafana datasources for both environments
- PrometheusRule-based alerting

### Scalability

- DaemonSet deployment for Alloy agents (auto-scales with nodes)
- StatefulSet deployment for monitoring backends
- Horizontal scaling support for applications

## Customization

### Adding More Applications

1. Create new overlays in `gitops/components/` for your application
2. Add to `instrumented-apps-appset.yaml`
3. Commit and push to Git
4. ArgoCD will automatically deploy

### Adjusting Resources

Edit resource limits in the base deployments:

- `gitops/components/monitoring/*/base/*-statefulset.yaml`
- `gitops/components/instrumented-app/base/app-deployment.yaml`
- `gitops/components/alloy-agent/base/alloy-daemonset.yaml`

### Custom Alerting Rules

Add more rules in `gitops/components/alerting-rules/base/app-prometheus-rules.yaml`

## Production Considerations

This setup is for demonstration. For production:

1. **Security**:

   - Enable Grafana authentication
   - Use TLS/HTTPS for all communications
   - Implement RBAC policies
   - Secure ArgoCD with proper authentication

2. **Storage**:

   - Use object storage (S3, GCS, Azure Blob) instead of filesystem
   - Configure proper retention policies
   - Set up backup strategies

3. **High Availability**:

   - Run multiple replicas of monitoring components
   - Use distributed deployment patterns
   - Configure proper resource requests/limits

4. **Networking**:

   - Use Ingress instead of NodePort
   - Implement network policies
   - Consider service mesh for mTLS

5. **Monitoring**:
   - Add Alertmanager for alert routing
   - Configure notification channels (Slack, PagerDuty, etc.)
   - Set up proper SLOs and SLIs

## Resources

- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/)
- [Grafana Documentation](https://grafana.com/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [Mimir Documentation](https://grafana.com/docs/mimir/latest/)
- [Prometheus Operator Documentation](https://prometheus-operator.dev/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)

## License

MIT
