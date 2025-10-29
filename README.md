# Multi-Tenant Observability Stack with Grafana Alloy

A production-ready multi-tenant observability platform using **Grafana Alloy**, the **LGTM+O stack** (Loki, Grafana, Tempo, Mimir, OpenTelemetry), and **MinIO** for object storage - all deployed across multiple Kubernetes clusters with GitOps using ArgoCD.

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Architecture Deep Dive](#architecture-deep-dive)
  - [Data Collection Flow](#data-collection-flow)
  - [Alerting Architecture](#alerting-architecture)
  - [Multi-Tenancy](#multi-tenancy)
- [Accessing Services](#accessing-services)
- [Troubleshooting](#troubleshooting)

## Architecture Overview

This setup simulates a production-like multi-cluster environment using minikube with complete tenant isolation:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         CONTROL CLUSTER                                   │
│                          (ArgoCD GitOps)                                  │
└────────────────────────────────┬─────────────────────────────────────────┘
                                 │ Manages deployments
                    ┌────────────┼────────────┐
                    │            │            │
                    ▼            ▼            ▼
    ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────────┐
    │  STAGE CLUSTER    │  │  PROD CLUSTER     │  │  MONITORING CLUSTER   │
    │                   │  │                   │  │                       │
    │ ┌───────────────┐ │  │ ┌───────────────┐ │  │ ┌─────────────────┐ │
    │ │ Applications  │ │  │ │ Applications  │ │  │ │ Grafana         │ │
    │ │ - Full OTEL   │ │  │ │ - Full OTEL   │ │  │ │ - Dashboards    │ │
    │ │ - Prom/OTEL   │ │  │ │ - Prom/OTEL   │ │  │ │ - Alerts UI     │ │
    │ └───────────────┘ │  │ └───────────────┘ │  │ └─────────────────┘ │
    │                   │  │                   │  │                       │
    │ ┌───────────────┐ │  │ ┌───────────────┐ │  │ ┌─────────────────┐ │
    │ │ Alloy Agents  │ │  │ │ Alloy Agents  │ │  │ │ Mimir           │ │
    │ │ - Metrics     │ │  │ │ - Metrics     │ │  │ │ - stage tenant  │ │
    │ │ - Logs        │ │  │ │ - Logs        │ │  │ │ - prod tenant   │ │
    │ │ - Traces      │ │  │ │ - Traces      │ │  │ │ - Alertmanager  │ │
    │ └───────┬───────┘ │  │ └───────┬───────┘ │  │ └─────────────────┘ │
    └─────────┼─────────┘  └─────────┼─────────┘  │                       │
              │                      │             │ ┌─────────────────┐ │
              │      Remote Write    │             │ │ Loki            │ │
              │      Push Logs/Traces│             │ │ - stage tenant  │ │
              └──────────────────────┼─────────────┤ │ - prod tenant   │ │
                                     │             │ │ - S3 rules      │ │
                                     └─────────────┤ └─────────────────┘ │
                                                   │                       │
                                                   │ ┌─────────────────┐ │
                                                   │ │ Tempo           │ │
                                                   │ │ - stage tenant  │ │
                                                   │ │ - prod tenant   │ │
                                                   │ └─────────────────┘ │
                                                   │                       │
                                                   │ ┌─────────────────┐ │
                                                   │ │ MinIO (S3)      │ │
                                                   │ │ - Loki rules    │ │
                                                   │ └─────────────────┘ │
                                                   │                       │
                                                   │ ┌─────────────────┐ │
                                                   │ │ Alloy-Alerts    │ │
                                                   │ │ - Rules sync    │ │
                                                   │ └─────────────────┘ │
                                                   └───────────────────────┘
```

### Key Components

#### Member Clusters (stage/prod)

- **Applications**: Flask apps with full OpenTelemetry instrumentation
- **Alloy Agents**: Separate DaemonSets for metrics, logs, and traces collection
- **Service Discovery**: Kubernetes service monitors and pod logs

#### Monitoring Cluster

- **Grafana**: Unified visualization with multi-tenant datasources
- **Mimir**: Multi-tenant metrics storage with built-in Alertmanager
- **Loki**: Multi-tenant log aggregation with ruler for log-based alerts
- **Tempo**: Multi-tenant distributed tracing
- **MinIO**: S3-compatible object storage for Loki ruler rules
- **Alloy-Alerts**: Dedicated component for syncing PrometheusRule CRDs to rulers

## Prerequisites

- **minikube** - For running multiple Kubernetes clusters
- **Docker** - Container runtime
- **kubectl** - Kubernetes CLI
- **argocd CLI** - For ArgoCD management
- **tmux** (or similar) - For managing multiple terminals
- At least **12GB RAM** available

## Quick Start

### 1. Setup Cluster Networking

```bash
./scripts/update-hosts-entry.sh
```

This configures `/etc/hosts` entries for accessing services via friendly names.

### 2. Start All Clusters

```bash
./.hack/clusters-up.sh
```

This will:

- Create 4 minikube clusters (control, stage, prod, monitoring)
- Install ArgoCD in the control cluster
- Register all clusters with ArgoCD
- Configure cross-cluster networking
- Display ArgoCD login credentials

**Action Required**: The script will pause and display ArgoCD credentials. Log in to the ArgoCD UI to verify it's accessible before continuing.

### 3. Deploy the Stack

Deploy in order using ArgoCD ApplicationSets:

```bash
# Ensure you're on control-cluster context
kubectl config use-context control-cluster

# Deploy monitoring stack (Grafana, Mimir, Loki, Tempo, MinIO, Alloy-Alerts)
kubectl apply -k gitops/appsets/app-of-appsets/overlays/monitoring --context control-cluster

# Deploy stage environment (apps + alloy agents)
kubectl apply -k gitops/appsets/app-of-appsets/overlays/stage --context control-cluster

# Deploy prod environment (apps + alloy agents)
kubectl apply -k gitops/appsets/app-of-appsets/overlays/prod --context control-cluster
```

**Wait for deployments**: Monitor ArgoCD UI or check pod status:

```bash
# Check monitoring stack
kubectl get pods -n monitoring --context monitoring-cluster

# Check stage apps and agents
kubectl get pods -n apps-stage --context stage-cluster
kubectl get pods -n alloy-system --context stage-cluster

# Check prod apps and agents
kubectl get pods -n apps-prod --context prod-cluster
kubectl get pods -n alloy-system --context prod-cluster
```

### 4. Setup Port Forwards

Use tmux or multiple terminals:

```bash
# Terminal 1: Grafana
./scripts/portforwards/port-forward-grafana.sh

# Terminal 2: Stage Full OTEL App
kubectl port-forward -n apps-stage svc/full-otel-instrumented-app 8282:8080 --context stage-cluster

# Terminal 3: Stage Prom/OTEL App
kubectl port-forward -n apps-stage svc/prom-otel-instrumented-app 8383:8080 --context stage-cluster

# Terminal 4: Prod Full OTEL App
kubectl port-forward -n apps-prod svc/full-otel-instrumented-app 9282:8080 --context prod-cluster

# Terminal 5: Prod Prom/OTEL App
kubectl port-forward -n apps-prod svc/prom-otel-instrumented-app 9383:8080 --context prod-cluster
```

### 5. Generate Traffic

In separate terminals:

```bash
# Generate traffic to stage apps
./scripts/generate-traffic.sh 8282    # Full OTEL app
./scripts/generate-traffic.sh 8383    # Prom/OTEL app

# Generate traffic to prod apps
./scripts/generate-traffic.sh 9282    # Full OTEL app
./scripts/generate-traffic.sh 9383    # Prom/OTEL app
```

### 6. Access Grafana

Open **http://localhost:3000** (default credentials: `admin/admin`)

You'll see datasources for both tenants:

- **Mimir-Stage** / **Mimir-Prod** - Metrics
- **Loki-Stage** / **Loki-Prod** - Logs
- **Tempo-Stage** / **Tempo-Prod** - Traces

### 7. Deploy Alert Rules

```bash
# Deploy metrics alert rules
kubectl apply -f o11y/alerting-rules/tenants/stage/app-alerts-stage.yaml --context monitoring-cluster
kubectl apply -f o11y/alerting-rules/tenants/prod/app-alerts-prod.yaml --context monitoring-cluster

# Deploy log alert rules
kubectl apply -f o11y/alerting-rules/tenants/stage/log-alerts-stage.yaml --context monitoring-cluster
kubectl apply -f o11y/alerting-rules/tenants/prod/log-alerts-prod.yaml --context monitoring-cluster
```

View alerts in Grafana: **Alerting → Alert rules**

---

## Architecture Deep Dive

### Data Collection Flow

Each tenant has dedicated Alloy agents that collect and forward telemetry data:

```
┌────────────────────────────────────────────────────────────────────────┐
│                       APPLICATION CLUSTER (Stage/Prod)                  │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐ │
│  │                        APPLICATIONS                               │ │
│  │                                                                   │ │
│  │  ┌─────────────────────┐        ┌─────────────────────┐         │ │
│  │  │ Full OTEL App       │        │ Prom/OTEL App       │         │ │
│  │  │                     │        │                     │         │ │
│  │  │ • OTEL SDK exports  │        │ • /metrics endpoint │         │ │
│  │  │   to OTEL Collector │        │ • OTEL SDK for logs │         │ │
│  │  │                     │        │   and traces        │         │ │
│  │  └──────────┬──────────┘        └──────────┬──────────┘         │ │
│  │             │ OTLP                          │ HTTP + OTLP        │ │
│  └─────────────┼───────────────────────────────┼────────────────────┘ │
│                │                               │                       │
│  ┌─────────────▼───────────────────────────────▼────────────────────┐ │
│  │                    GRAFANA ALLOY AGENTS                           │ │
│  │                                                                   │ │
│  │  ┌────────────────┐  ┌────────────────┐  ┌────────────────┐    │ │
│  │  │ alloy-metrics  │  │  alloy-logs    │  │ alloy-traces   │    │ │
│  │  │                │  │                │  │                │    │ │
│  │  │ Discovers:     │  │ Discovers:     │  │ Receives:      │    │ │
│  │  │ • ServiceMon   │  │ • PodLogs CRD  │  │ • OTLP traces  │    │ │
│  │  │ • /metrics     │  │ • Pod logs     │  │ • Tail-based   │    │ │
│  │  │                │  │                │  │   sampling     │    │ │
│  │  │ Scrapes via:   │  │ Collects via:  │  │                │    │ │
│  │  │ • HTTP polling │  │ • Loki.source  │  │ Forwards via:  │    │ │
│  │  │                │  │   .kubernetes  │  │ • OTLP/HTTP    │    │ │
│  │  │ Forwards via:  │  │                │  │                │    │ │
│  │  │ • remote_write │  │ Forwards via:  │  │                │    │ │
│  │  │   (Prometheus) │  │ • Loki HTTP    │  │                │    │ │
│  │  └────────┬───────┘  └────────┬───────┘  └────────┬───────┘    │ │
│  └───────────┼──────────────────────┼──────────────────────┼────────┘ │
└──────────────┼──────────────────────┼──────────────────────┼──────────┘
               │                      │                      │
               │ Tenant-specific      │ Tenant-specific      │ Tenant-specific
               │ Headers:             │ Headers:             │ Headers:
               │ X-Scope-OrgID:stage  │ X-Scope-OrgID:stage  │ X-Scope-OrgID:stage
               │                      │                      │
               ▼                      ▼                      ▼
┌────────────────────────────────────────────────────────────────────────┐
│                         MONITORING CLUSTER                              │
│                                                                         │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐    │
│  │  MIMIR           │  │  LOKI            │  │  TEMPO           │    │
│  │                  │  │                  │  │                  │    │
│  │  Port: 9009      │  │  Port: 3100      │  │  Port: 3200      │    │
│  │                  │  │                  │  │                  │    │
│  │  ┌────────────┐  │  │  ┌────────────┐  │  │  ┌────────────┐  │    │
│  │  │ stage      │  │  │  │ stage      │  │  │  │ stage      │  │    │
│  │  │ tenant     │  │  │  │ tenant     │  │  │  │ tenant     │  │    │
│  │  │ metrics    │  │  │  │ logs       │  │  │  │ traces     │  │    │
│  │  └────────────┘  │  │  └────────────┘  │  │  └────────────┘  │    │
│  │                  │  │                  │  │                  │    │
│  │  ┌────────────┐  │  │  ┌────────────┐  │  │  ┌────────────┐  │    │
│  │  │ prod       │  │  │  │ prod       │  │  │  │ prod       │  │    │
│  │  │ tenant     │  │  │  │ tenant     │  │  │  │ tenant     │  │    │
│  │  │ metrics    │  │  │  │ logs       │  │  │  │ traces     │  │    │
│  │  └────────────┘  │  │  └────────────┘  │  │  └────────────┘  │    │
│  └──────────────────┘  └──────────────────┘  └──────────────────┘    │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────┐    │
│  │                       GRAFANA                                  │    │
│  │                                                                │    │
│  │  Multi-tenant datasources with X-Scope-OrgID headers          │    │
│  │  • Query each tenant's data independently                     │    │
│  │  • Unified dashboards with tenant filtering                   │    │
│  │  • Alert visualization from Mimir AlertManager                │    │
│  └───────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────┘
```

#### Component Responsibilities

| Component         | DaemonSet      | Purpose                   | Discovers           | Forwards To          |
| ----------------- | -------------- | ------------------------- | ------------------- | -------------------- |
| **alloy-metrics** | ✓              | Scrape Prometheus metrics | ServiceMonitors     | Mimir (remote_write) |
| **alloy-logs**    | ✓              | Collect pod logs          | PodLogs CRD         | Loki (HTTP push)     |
| **alloy-traces**  | ✓              | Receive and sample traces | OTLP receivers      | Tempo (OTLP)         |
| **alloy-alerts**  | ✗ (Deployment) | Sync alert rules          | PrometheusRule CRDs | Mimir/Loki rulers    |

### Alerting Architecture

The alerting system uses a unified approach with PrometheusRule CRDs for both metrics and log-based alerts:

```
┌─────────────────────────────────────────────────────────────────────────┐
│              KUBERNETES API (monitoring-cluster)                         │
│                                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    PrometheusRule CRDs                            │  │
│  │                                                                   │  │
│  │  ┌─────────────────────┐      ┌─────────────────────┐           │  │
│  │  │ Metrics Rules       │      │ Log Rules           │           │  │
│  │  │                     │      │                     │           │  │
│  │  │ labels:             │      │ labels:             │           │  │
│  │  │   tenant: stage     │      │   tenant: stage     │           │  │
│  │  │   type: metrics ◄───┼──┐   │   type: logs    ◄───┼──┐        │  │
│  │  │                     │  │   │                     │  │        │  │
│  │  │ spec:               │  │   │ spec:               │  │        │  │
│  │  │   expr: |           │  │   │   expr: |           │  │        │  │
│  │  │     rate(errors[5m])│  │   │     rate({level=    │  │        │  │
│  │  │       > 0.05        │  │   │       "error"}[5m]) │  │        │  │
│  │  │     ↑ PromQL        │  │   │     ↑ LogQL         │  │        │  │
│  │  └─────────────────────┘  │   └─────────────────────┘  │        │  │
│  └───────────────────────────┼──────────────────────────────┼────────┘  │
└───────────────────────────────┼──────────────────────────────┼──────────┘
                                │ Watches                      │ Watches
                                │ (label selector)             │ (label selector)
                                ▼                              ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                       ALLOY-ALERTS (Deployment)                           │
│                                                                           │
│  ┌────────────────────────────┐    ┌──────────────────────────┐         │
│  │ mimir.rules.kubernetes     │    │ loki.rules.kubernetes    │         │
│  │                            │    │                          │         │
│  │ address:                   │    │ address:                 │         │
│  │   mimir:9009               │    │   loki:3100              │         │
│  │                            │    │                          │         │
│  │ rule_selector:             │    │ rule_selector:           │         │
│  │   tenant = stage           │    │   tenant = stage         │         │
│  │   type = metrics           │    │   type = logs            │         │
│  │                            │    │                          │         │
│  │ tenant_id: "stage"         │    │ tenant_id: "stage"       │         │
│  └──────────────┬─────────────┘    └──────────────┬───────────┘         │
└─────────────────┼──────────────────────────────────┼─────────────────────┘
                  │ Syncs via API                    │ Syncs via API
                  │ (X-Scope-OrgID: stage)           │ (X-Scope-OrgID: stage)
                  ▼                                  ▼
┌──────────────────────────┐          ┌──────────────────────────┐
│  MIMIR                   │          │  LOKI                    │
│                          │          │                          │
│  ┌────────────────────┐  │          │  ┌────────────────────┐  │
│  │ Mimir Ruler        │  │          │  │ Loki Ruler         │  │
│  │                    │  │          │  │                    │  │
│  │ Storage:           │  │          │  │ Storage:           │  │
│  │ • Filesystem for   │  │          │  │ • MinIO (S3) for   │  │
│  │   rule metadata    │  │          │  │   rule storage     │  │
│  │                    │  │          │  │ • API-compatible   │  │
│  │ Evaluates:         │  │          │  │                    │  │
│  │ • PromQL queries   │  │          │  │ Evaluates:         │  │
│  │ • Against Mimir    │  │          │  │ • LogQL queries    │  │
│  │   metrics          │  │          │  │ • Against Loki     │  │
│  │ • Per-tenant       │  │          │  │   logs             │  │
│  │   isolation        │  │          │  │ • Per-tenant       │  │
│  │                    │  │          │  │   isolation        │  │
│  └─────────┬──────────┘  │          │  └─────────┬──────────┘  │
│            │ Fires alerts│          │            │ Fires alerts│
│            ▼             │          │            │             │
│  ┌────────────────────┐  │          │  alertmanager_url:      │
│  │ Mimir              │◄─┼──────────┼──http://mimir:9009/     │
│  │ AlertManager       │  │          │  alertmanager           │
│  │                    │  │          │  (X-Scope-OrgID header) │
│  │ • Multi-tenant     │  │          └──────────────────────────┘
│  │ • Unified alerts   │  │
│  │   from Mimir +     │  │
│  │   Loki rulers      │  │
│  │                    │  │
│  │ • Deduplication    │  │
│  │ • Grouping         │  │
│  │ • Routing by       │  │
│  │   tenant labels    │  │
│  │                    │  │
│  │ • Silencing        │  │
│  │ • Inhibition       │  │
│  └─────────┬──────────┘  │
└────────────┼─────────────┘
             │
             │ Routes based on tenant & severity
             ▼
┌─────────────────────────────────────────┐
│       Notification Channels              │
│                                         │
│  ┌──────────┐  ┌──────────┐            │
│  │ Grafana  │  │  Slack   │            │
│  │ Alerting │  │ Webhooks │            │
│  │   UI     │  └──────────┘            │
│  │          │                           │
│  │ • View   │  ┌──────────┐            │
│  │   alerts │  │PagerDuty │            │
│  │ • Create │  └──────────┘            │
│  │   silence│                           │
│  │ • Manage │  ┌──────────┐            │
│  │   routes │  │  Email   │            │
│  └──────────┘  └──────────┘            │
└─────────────────────────────────────────┘
```

#### Alert Rule Types

| Type        | Language | Evaluated By | Example Query                                  |
| ----------- | -------- | ------------ | ---------------------------------------------- |
| **Metrics** | PromQL   | Mimir Ruler  | `rate(http_requests_errors[5m]) > 0.05`        |
| **Logs**    | LogQL    | Loki Ruler   | `sum(rate({level="error"}[5m])) by (app) > 10` |

Both types:

- Use the same `PrometheusRule` CRD format
- Support the same alert labels and annotations
- Send alerts to the same Mimir AlertManager
- Respect tenant isolation via `X-Scope-OrgID`

#### Storage Architecture

**Mimir Ruler**: Uses local filesystem for rule storage (simple, works out of the box)

**Loki Ruler**: Uses **MinIO** (S3-compatible object storage) because:

- Local filesystem storage doesn't support API-based rule management
- MinIO provides S3-compatible APIs that Loki's ruler requires
- Enables dynamic rule updates via `loki.rules.kubernetes`
- Production-ready pattern with in-cluster object storage

```
┌──────────────────────────────────────────┐
│         MinIO StatefulSet                 │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │ S3-Compatible Object Storage       │ │
│  │                                    │ │
│  │ Bucket: loki-ruler                 │ │
│  │                                    │ │
│  │ /stage/                            │ │
│  │   └── rule-groups/                 │ │
│  │       └── log-alerts-stage.yaml    │ │
│  │                                    │ │
│  │ /prod/                             │ │
│  │   └── rule-groups/                 │ │
│  │       └── log-alerts-prod.yaml     │ │
│  └────────────────────────────────────┘ │
└──────────────────────────────────────────┘
         ▲
         │ S3 API calls
         │ (GetObject, PutObject)
         │
┌────────┴──────────────────────────────────┐
│  Loki Ruler Configuration                 │
│                                           │
│  ruler:                                   │
│    storage:                               │
│      type: s3                             │
│      s3:                                  │
│        endpoint: minio:9000               │
│        bucketnames: loki-ruler            │
│        access_key_id: minio               │
│        secret_access_key: minio123        │
│        insecure: true                     │
│        s3forcepathstyle: true             │
└───────────────────────────────────────────┘
```

### Multi-Tenancy

Complete data isolation is achieved through:

#### 1. Tenant-Specific Headers

All telemetry data is tagged with tenant ID:

```yaml
# Alloy agents forward with headers
remote_write:
  - url: http://mimir:9009/api/v1/push
    headers:
      X-Scope-OrgID: stage # or prod

# Grafana datasources query with headers
jsonData:
  httpHeaderName1: "X-Scope-OrgID"
secureJsonData:
  httpHeaderValue1: "stage" # or prod
```

#### 2. Storage Isolation

```
Mimir (Metrics):
├── /data/mimir/tsdb/stage/     # Stage metrics
├── /data/mimir/tsdb/prod/      # Prod metrics
├── /data/mimir/rules/stage/    # Stage metric rules
└── /data/mimir/rules/prod/     # Prod metric rules

Loki (Logs):
├── /loki/chunks/stage/         # Stage logs
├── /loki/chunks/prod/          # Prod logs
└── MinIO S3:
    ├── /loki-ruler/stage/      # Stage log rules
    └── /loki-ruler/prod/       # Prod log rules

Tempo (Traces):
├── /tempo/blocks/stage/        # Stage traces
└── /tempo/blocks/prod/         # Prod traces
```

#### 3. Rule Evaluation Isolation

```
┌──────────────────────────────────────────┐
│  Mimir Ruler (stage tenant)              │
│                                          │
│  Query: rate(http_requests[5m])         │
│  ↓                                       │
│  Queries only stage tenant's metrics    │
│  (X-Scope-OrgID: stage)                 │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│  Loki Ruler (prod tenant)                │
│                                          │
│  Query: rate({level="error"}[5m])       │
│  ↓                                       │
│  Queries only prod tenant's logs        │
│  (X-Scope-OrgID: prod)                  │
└──────────────────────────────────────────┘
```

#### 4. Alert Routing Isolation

Alerts are routed based on tenant label:

```yaml
# Mimir AlertManager config
route:
  group_by: ["alertname", "tenant", "cluster"]
  receiver: "default-receiver"

  routes:
    - receiver: "stage-team"
      matchers:
        - tenant="stage"

    - receiver: "prod-oncall"
      matchers:
        - tenant="prod"
        - severity=~"critical|warning"
```

## Accessing Services

### Grafana

**URL**: http://localhost:3000 (after port-forward)  
**Default Credentials**: `admin / admin`

#### Available Datasources

**Stage Environment**:

- `Mimir-Stage` - Metrics (PromQL)
- `Loki-Stage` - Logs (LogQL)
- `Tempo-Stage` - Traces

**Prod Environment**:

- `Mimir-Prod` - Metrics (PromQL)
- `Loki-Prod` - Logs (LogQL)
- `Tempo-Prod` - Traces

#### Viewing Alerts

Navigate to **Alerting → Alert rules** to see:

- Metrics alerts from Mimir ruler
- Log alerts from Loki ruler
- Alert status (Normal, Pending, Firing)
- Filter by tenant and type

#### Example Queries

**Metrics**:

```promql
# Request rate by app
rate(http_requests_total[5m])

# Error rate
rate(http_requests_total{status=~"5.."}[5m])

# 95th percentile latency
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))
```

**Logs**:

```logql
# All application logs
{app="full-otel-instrumented-app"}

# Error logs only
{app="full-otel-instrumented-app"} |= "error"

# Log rate
rate({app="full-otel-instrumented-app"}[5m])
```

**Traces**:

- Search by service name: `full-otel-instrumented-app-stage`
- Filter by duration, tags, or errors
- Click trace IDs in logs to jump to traces

### Application Endpoints

Access applications via port-forward:

**Stage Apps**:

- Full OTEL: http://localhost:8282
- Prom/OTEL: http://localhost:8383

**Prod Apps**:

- Full OTEL: http://localhost:9282
- Prom/OTEL: http://localhost:9383

**Available Endpoints**:

```bash
# Health check
curl http://localhost:8282/health

# Generate normal requests
curl http://localhost:8282/
curl http://localhost:8282/api/users
curl http://localhost:8282/api/data

# Generate slow requests (latency)
curl http://localhost:8282/api/slow

# Generate errors
curl http://localhost:8282/api/error
```

## Troubleshooting

### Check Cluster Status

```bash
./scripts/get-cluster-info.sh
```

### Check Pod Status

```bash
# Monitoring stack
kubectl get pods -n monitoring --context monitoring-cluster

# Stage environment
kubectl get pods -n apps-stage --context stage-cluster
kubectl get pods -n alloy-system --context stage-cluster

# Prod environment
kubectl get pods -n apps-prod --context prod-cluster
kubectl get pods -n alloy-system --context prod-cluster
```

### Check Alloy Agent Logs

```bash
# Metrics agent
kubectl logs -n alloy-system -l app.kubernetes.io/name=alloy-metrics --context stage-cluster -f

# Logs agent
kubectl logs -n alloy-system -l app.kubernetes.io/name=alloy-logs --context stage-cluster -f

# Traces agent
kubectl logs -n alloy-system -l app.kubernetes.io/name=alloy-traces --context stage-cluster -f
```

### Check Alert Rule Syncing

```bash
# Port-forward services first
kubectl port-forward -n monitoring svc/mimir 9009:9009 --context monitoring-cluster &
kubectl port-forward -n monitoring svc/loki 3100:3100 --context monitoring-cluster &

# Check metrics rules (stage)
curl -H "X-Scope-OrgID: stage" http://localhost:9009/prometheus/api/v1/rules | jq

# Check log rules (stage)
curl -H "X-Scope-OrgID: stage" http://localhost:3100/loki/api/v1/rules | jq

# Check alloy-alerts logs
kubectl logs -n alloy-system -l app=alloy-alerts --context monitoring-cluster -f
```

### Verify Data Flow

```bash
# Check if Mimir is receiving metrics
curl -H "X-Scope-OrgID: stage" 'http://localhost:9009/prometheus/api/v1/query?query=up' | jq

# Check if Loki is receiving logs
curl -H "X-Scope-OrgID: stage" 'http://localhost:3100/loki/api/v1/labels' | jq

# Check active alerts
curl -H "X-Scope-OrgID: stage" http://localhost:9009/alertmanager/api/v2/alerts | jq
```

### Common Issues

**1. Pods stuck in Pending**:

- Check if minikube has enough resources: `minikube status`
- Increase resources: `minikube config set memory 12288`

**2. Alloy agents can't connect to monitoring cluster**:

- Verify NodePort services: `kubectl get svc -n monitoring --context monitoring-cluster`
- Check network connectivity: `kubectl exec -it <pod> --context stage-cluster -- curl http://<monitoring-ip>:9009/ready`

**3. No metrics/logs appearing in Grafana**:

- Check if applications are running and generating data
- Verify Alloy agent logs for connection errors
- Confirm datasource configuration in Grafana

**4. Rules not syncing**:

- Verify PrometheusRule CRDs have correct labels (`tenant` and `type`)
- Check alloy-alerts component logs
- Ensure Prometheus Operator CRDs are installed

**5. MinIO bucket not created**:

- Check init job status: `kubectl get jobs -n monitoring --context monitoring-cluster`
- View job logs: `kubectl logs -n monitoring job/minio-init-buckets --context monitoring-cluster`

## Cleanup

To tear down all clusters:

```bash
./.hack/clusters-down.sh
```

This will delete all 4 minikube clusters and their data.

## Project Structure

```
.
├── .hack/                           # Cluster lifecycle scripts
│   ├── clusters-up.sh               # Start all clusters
│   └── clusters-down.sh             # Stop all clusters
│
├── apps/                            # Application source code
│   ├── full-otel-instrumented-app/  # Full OTEL SDK app
│   └── prom-otel-instrumented-app/  # Prometheus + OTEL app
│
├── gitops/                          # GitOps manifests
│   ├── appsets/                     # ArgoCD ApplicationSets
│   │   ├── app-of-appsets/          # App of Apps pattern
│   │   │   └── overlays/
│   │   │       ├── monitoring/      # Monitoring stack apps
│   │   │       ├── stage/           # Stage environment apps
│   │   │       └── prod/            # Prod environment apps
│   │   └── base/                    # Base ApplicationSets
│   │
│   └── components/                  # Application components
│       ├── alloy-metrics/           # Metrics collection
│       ├── alloy-logs/              # Logs collection
│       ├── alloy-traces/            # Traces collection
│       ├── full-otel-instrumented-app/
│       ├── prom-otel-instrumented-app/
│       ├── operators/               # Alloy & Prometheus operators
│       └── monitoring/              # Monitoring stack
│           ├── grafana/
│           ├── mimir/
│           ├── loki/
│           ├── tempo/
│           ├── minio/               # S3 storage for Loki rules
│           └── alloy-alerts/        # Alert rules syncing
│
├── o11y/                            # Observability configuration
│   └── alerting-rules/              # PrometheusRule CRDs
│       └── tenants/
│           ├── stage/
│           │   ├── app-alerts-stage.yaml    # Metrics alerts
│           │   └── log-alerts-stage.yaml    # Log alerts
│           └── prod/
│               ├── app-alerts-prod.yaml     # Metrics alerts
│               └── log-alerts-prod.yaml     # Log alerts
│
└── scripts/                         # Helper scripts
    ├── generate-traffic.sh          # Traffic generator
    ├── get-cluster-info.sh          # Cluster information
    ├── update-alloy-agents-endpoints.sh
    ├── update-hosts-entry.sh
    └── portforwards/
        └── port-forward-grafana.sh
```

## Key Features

### ✨ Production-Ready Patterns

- **GitOps**: Declarative infrastructure managed via ArgoCD
- **Multi-Tenancy**: Complete isolation at storage and query level
- **Object Storage**: MinIO for Loki ruler rules (S3-compatible)
- **Service Discovery**: Automatic with ServiceMonitors and PodLogs CRDs
- **Tail-Based Sampling**: Intelligent trace sampling in Alloy
- **Unified Alerting**: Single AlertManager for all alert types

### 🔒 Security & Isolation

- Per-tenant data storage and access control
- Separate Alloy agent instances per telemetry type
- Network policies (can be enabled)
- RBAC for Kubernetes resources

### 📊 Observability

- Full OpenTelemetry instrumentation
- Trace-to-logs correlation via trace IDs
- Multi-dimensional metrics with labels
- Structured logging
- Distributed tracing with context propagation

### 🚀 Scalability

- DaemonSet deployment for agents (auto-scales with nodes)
- StatefulSet deployment for monitoring backends
- Horizontal scaling ready for applications
- Configurable retention and sampling policies

## Production Considerations

This setup is designed for learning and POC. For production:

1. **Storage**:

   - Use real S3/GCS/Azure for object storage
   - Configure proper retention policies
   - Set up backup strategies

2. **Security**:

   - Enable TLS/HTTPS for all communications
   - Implement proper RBAC and network policies
   - Use Secrets management (Vault, Sealed Secrets)
   - Enable authentication in Grafana

3. **High Availability**:

   - Run multiple replicas of monitoring components
   - Use distributed deployment patterns
   - Configure proper resource requests/limits
   - Set up alerting for infrastructure

4. **Networking**:

   - Use Ingress controllers instead of NodePort
   - Implement service mesh for mTLS
   - Configure proper DNS

5. **Alerting**:
   - Set up notification channels (Slack, PagerDuty)
   - Define SLOs and SLIs
   - Create runbooks and documentation

## Resources

- [Grafana Alloy Documentation](https://grafana.com/docs/alloy/latest/)
- [Grafana Mimir Documentation](https://grafana.com/docs/mimir/latest/)
- [Grafana Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Grafana Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [MinIO Documentation](https://min.io/docs/minio/kubernetes/upstream/)

## License

MIT
