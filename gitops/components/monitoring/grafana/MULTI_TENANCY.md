# Grafana Multi-Tenancy Architecture

## Current Setup: Platform Admin View

The current Grafana deployment is configured as a **single instance with all tenant datasources visible**. This is designed for platform administrators and operators who need to monitor and troubleshoot all tenants.

### Current Configuration

```
┌──────────────────────────────────────────────────────────────┐
│              Grafana (Single Instance)                        │
│              http://localhost:3000                            │
│                                                               │
│  All Datasources Visible:                                    │
│  ┌────────────────────┐  ┌────────────────────┐             │
│  │ Stage Tenant       │  │ Prod Tenant        │             │
│  │                    │  │                    │             │
│  │ • Mimir-Stage      │  │ • Mimir-Prod       │             │
│  │ • Loki-Stage       │  │ • Loki-Prod        │             │
│  │ • Tempo-Stage      │  │ • Tempo-Prod       │             │
│  └────────────────────┘  └────────────────────┘             │
│                                                               │
│  Users: Anyone with credentials (admin/admin)                │
│  Can: Switch between any datasource and see all data         │
└──────────────────────────────────────────────────────────────┘
```

### Use Cases

This setup is appropriate for:

✅ **Platform Operators**: SRE/DevOps teams managing the observability infrastructure  
✅ **Development/POC**: Demonstrating multi-tenancy at the backend level  
✅ **Troubleshooting**: Quick access to all tenant data for debugging  
✅ **Cross-Tenant Monitoring**: Dashboards comparing metrics across tenants

❌ **NOT appropriate for**: Giving tenants direct access to Grafana

## Production Multi-Tenancy Options

For production environments where **tenants should only see their own data**, you have several architectural options:

---

## Option 1: Separate Grafana Instances per Tenant

### Architecture

Deploy one Grafana instance per tenant, each with only that tenant's datasources:

```
┌─────────────────────────────────────────────────┐
│  Grafana-Stage                                  │
│  URL: https://grafana-stage.example.com         │
│  Namespace: monitoring-stage                    │
│                                                 │
│  Datasources:                                   │
│  ✓ Mimir-Stage  (X-Scope-OrgID: stage)         │
│  ✓ Loki-Stage   (X-Scope-OrgID: stage)         │
│  ✓ Tempo-Stage  (X-Scope-OrgID: stage)         │
│                                                 │
│  Users: Stage team members only                 │
│  Authentication: LDAP/OAuth for stage-team      │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  Grafana-Prod                                   │
│  URL: https://grafana-prod.example.com          │
│  Namespace: monitoring-prod                     │
│                                                 │
│  Datasources:                                   │
│  ✓ Mimir-Prod   (X-Scope-OrgID: prod)          │
│  ✓ Loki-Prod    (X-Scope-OrgID: prod)          │
│  ✓ Tempo-Prod   (X-Scope-OrgID: prod)          │
│                                                 │
│  Users: Prod team members only                  │
│  Authentication: LDAP/OAuth for prod-team       │
└─────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────┐
│  Grafana-Platform (Optional)                    │
│  URL: https://grafana-admin.example.com         │
│  Namespace: monitoring                          │
│                                                 │
│  Datasources: All tenants                       │
│  Users: Platform admins only                    │
│  Authentication: Admin-only OAuth               │
└─────────────────────────────────────────────────┘
```

### Implementation

Create separate overlays:

```
gitops/components/monitoring/grafana/
├── base/
│   ├── grafana-deployment.yaml
│   ├── grafana-service.yaml
│   └── kustomization.yaml
└── overlays/
    ├── stage/
    │   ├── grafana-datasources.yaml    # Only stage datasources
    │   ├── kustomization.yaml
    │   └── namespace.yaml              # monitoring-stage
    ├── prod/
    │   ├── grafana-datasources.yaml    # Only prod datasources
    │   ├── kustomization.yaml
    │   └── namespace.yaml              # monitoring-prod
    └── platform/
        ├── grafana-datasources.yaml    # All datasources
        ├── kustomization.yaml
        └── namespace.yaml              # monitoring
```

**Example Stage Datasources**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-datasources
  namespace: monitoring-stage
data:
  datasources.yaml: |
    apiVersion: 1
    datasources:
      - name: Mimir
        type: prometheus
        url: http://mimir.monitoring.svc.cluster.local:9009/prometheus
        isDefault: true
        jsonData:
          httpHeaderName1: 'X-Scope-OrgID'
          manageAlerts: true
        secureJsonData:
          httpHeaderValue1: 'stage'
      
      - name: Loki
        type: loki
        url: http://loki.monitoring.svc.cluster.local:3100
        jsonData:
          httpHeaderName1: 'X-Scope-OrgID'
          manageAlerts: true
        secureJsonData:
          httpHeaderValue1: 'stage'
      
      - name: Tempo
        type: tempo
        url: http://tempo.monitoring.svc.cluster.local:3200
        jsonData:
          httpHeaderName1: 'X-Scope-OrgID'
        secureJsonData:
          httpHeaderValue1: 'stage'
```

### Pros & Cons

**Pros**:

- ✅ Complete data isolation (impossible to see other tenant's data)
- ✅ Independent Grafana versions and plugin installations per tenant
- ✅ Tenant-specific authentication and authorization
- ✅ Simple to understand and secure
- ✅ Can customize Grafana settings per tenant
- ✅ Resource quotas per tenant

**Cons**:

- ❌ More resources required (multiple Grafana instances)
- ❌ Dashboard updates need to be replicated across instances
- ❌ No unified platform view (need separate platform instance)
- ❌ Operational overhead of managing multiple Grafanas

### Best For

- Strong tenant isolation requirements
- Different teams managing their own Grafana
- Tenants requiring different Grafana plugins or versions
- Billing/chargeback scenarios

---

## Option 2: Grafana Organizations (Native Multi-Tenancy)

### Architecture

Use Grafana's built-in Organizations feature to create tenant boundaries within a single Grafana instance:

```
┌───────────────────────────────────────────────────────────────┐
│                Grafana (Single Instance)                       │
│                http://localhost:3000                           │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ Organization: stage                                       │ │
│  │ ├── Datasources: Mimir/Loki/Tempo-Stage only            │ │
│  │ ├── Users: alice@stage.com, bob@stage.com               │ │
│  │ ├── Dashboards: Stage-specific dashboards                │ │
│  │ └── Folders: Private to stage org                        │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ Organization: prod                                        │ │
│  │ ├── Datasources: Mimir/Loki/Tempo-Prod only             │ │
│  │ ├── Users: charlie@prod.com, david@prod.com             │ │
│  │ ├── Dashboards: Prod-specific dashboards                 │ │
│  │ └── Folders: Private to prod org                         │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ Organization: platform (Main Org, ID: 1)                 │ │
│  │ ├── Datasources: All tenants                             │ │
│  │ ├── Users: admin@platform.com                            │ │
│  │ ├── Dashboards: Cross-tenant monitoring                  │ │
│  │ └── Admin Access: Can manage all organizations           │ │
│  └──────────────────────────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────┘
```

### Implementation

Configure via Grafana API or provisioning:

**1. Create Organizations**:

```bash
# Create stage organization
curl -X POST http://admin:admin@localhost:3000/api/orgs \
  -H "Content-Type: application/json" \
  -d '{"name": "stage"}'

# Create prod organization
curl -X POST http://admin:admin@localhost:3000/api/orgs \
  -H "Content-Type: application/json" \
  -d '{"name": "prod"}'
```

**2. Provision Datasources per Organization**:

```yaml
# grafana-datasources-stage.yaml
apiVersion: 1
datasources:
  - name: Mimir
    type: prometheus
    url: http://mimir:9009/prometheus
    orgId: 2 # stage organization
    jsonData:
      httpHeaderName1: "X-Scope-OrgID"
    secureJsonData:
      httpHeaderValue1: "stage"
```

**3. Add Users to Organizations**:

```bash
# Add user to stage org
curl -X POST http://admin:admin@localhost:3000/api/orgs/2/users \
  -H "Content-Type: application/json" \
  -d '{
    "loginOrEmail": "alice@stage.com",
    "role": "Admin"
  }'
```

**4. Configure Authentication**:

```ini
# grafana.ini
[auth]
disable_login_form = false

[auth.ldap]
enabled = true
config_file = /etc/grafana/ldap.toml

[users]
# Auto-assign users to organizations based on LDAP groups
auto_assign_org = true
auto_assign_org_id = 1
```

### Pros & Cons

**Pros**:

- ✅ Single Grafana instance (less resource overhead)
- ✅ Complete data isolation between organizations
- ✅ Built-in Grafana feature (no external dependencies)
- ✅ Unified user management
- ✅ Easier to maintain (single version, single upgrade)

**Cons**:

- ❌ Users can only belong to one organization at login
- ❌ Switching organizations requires logout/login
- ❌ Dashboards cannot be shared across organizations
- ❌ Alert rules are per-organization (no cross-tenant alerting)
- ❌ More complex user onboarding

### Best For

- Medium isolation requirements
- Unified Grafana management preferred
- Users don't need to switch between tenants frequently
- Centralized authentication system

---

## Option 3: Teams with RBAC (Grafana Enterprise)

### Architecture

Use Grafana Teams combined with datasource-level permissions:

```
┌───────────────────────────────────────────────────────────────┐
│              Grafana (Single Instance)                         │
│                                                                │
│  Teams:                                                        │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ stage-team  │  │ prod-team   │  │ admin-team  │          │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘          │
│         │                │                │                   │
│         │ Permissions    │ Permissions    │ Full Access       │
│         ▼                ▼                ▼                   │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ Datasources:│  │ Datasources:│  │ Datasources:│          │
│  │ - Mimir-Stg │  │ - Mimir-Prd │  │ - All       │          │
│  │ - Loki-Stg  │  │ - Loki-Prd  │  │ - All       │          │
│  │ - Tempo-Stg │  │ - Tempo-Prd │  │ - All       │          │
│  └─────────────┘  └─────────────┘  └─────────────┘          │
│                                                                │
│  Users can be in multiple teams                               │
│  Dashboards can use variables for tenant selection            │
└───────────────────────────────────────────────────────────────┘
```

### Implementation

**Requires Grafana Enterprise** or external authentication proxy.

**1. Create Teams**:

```bash
# Create stage team
curl -X POST http://admin:admin@localhost:3000/api/teams \
  -H "Content-Type: application/json" \
  -d '{"name": "stage-team"}'

# Create prod team
curl -X POST http://admin:admin@localhost:3000/api/teams \
  -H "Content-Type: application/json" \
  -d '{"name": "prod-team"}'
```

**2. Set Datasource Permissions**:

```bash
# Grant stage-team access to Mimir-Stage
curl -X POST http://admin:admin@localhost:3000/api/datasources/1/permissions \
  -H "Content-Type: application/json" \
  -d '{
    "teamId": 2,
    "permission": "Query"
  }'
```

**3. Assign Users to Teams**:

```bash
curl -X POST http://admin:admin@localhost:3000/api/teams/2/members \
  -H "Content-Type: application/json" \
  -d '{"userId": 3}'
```

### Pros & Cons

**Pros**:

- ✅ Fine-grained permission control
- ✅ Users can belong to multiple teams (if needed)
- ✅ Shared dashboards with variable tenant selection
- ✅ Flexible for complex scenarios
- ✅ Single Grafana instance

**Cons**:

- ❌ **Requires Grafana Enterprise** (for datasource permissions)
- ❌ More complex to configure and maintain
- ❌ Potential for misconfiguration allowing unauthorized access
- ❌ Users can still see datasource names (even if can't query)

### Best For

- Organizations already using Grafana Enterprise
- Complex multi-tenancy with overlapping team structures
- Need for cross-tenant dashboards with controlled access

---

## Option 4: Auth Proxy with Dynamic Headers

### Architecture

Use an authentication proxy that dynamically injects tenant context based on user identity:

```
┌────────────────────────────────────────────────────────────────┐
│  Auth Proxy (OAuth2-Proxy / Ambassador / Nginx)               │
│                                                                │
│  User Login: alice@example.com                                │
│  ├─> Extract tenant from: JWT claim / LDAP group / Header     │
│  ├─> Set Grafana headers:                                     │
│  │   └─> X-Grafana-Tenant: stage                             │
│  └─> Forward to Grafana                                       │
└──────────────────┬─────────────────────────────────────────────┘
                   │
                   ▼
┌────────────────────────────────────────────────────────────────┐
│                    Grafana                                      │
│                                                                │
│  Datasources with Variables:                                  │
│  ┌──────────────────────────────────────────────────────────┐ │
│  │ Mimir                                                     │ │
│  │ URL: http://mimir:9009/prometheus                        │ │
│  │ Headers:                                                  │ │
│  │   X-Scope-OrgID: ${__header.X-Grafana-Tenant}            │ │
│  └──────────────────────────────────────────────────────────┘ │
│                                                                │
│  User sees only their tenant's data automatically             │
│  No datasource switching - tenant from authentication         │
└────────────────────────────────────────────────────────────────┘
```

### Implementation Example (OAuth2-Proxy)

**1. Deploy OAuth2-Proxy**:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: oauth2-proxy
spec:
  template:
    spec:
      containers:
        - name: oauth2-proxy
          image: quay.io/oauth2-proxy/oauth2-proxy:latest
          args:
            - --provider=oidc
            - --oidc-issuer-url=https://auth.example.com
            - --email-domain=*
            - --upstream=http://grafana:3000
            - --pass-access-token=true
            - --pass-user-headers=true
            - --set-xauthrequest=true
          env:
            - name: OAUTH2_PROXY_CLIENT_ID
              value: "grafana-client"
            - name: OAUTH2_PROXY_CLIENT_SECRET
              valueFrom:
                secretKeyRef:
                  name: oauth-secret
                  key: client-secret
```

**2. Extract Tenant from JWT**:

```yaml
# Custom header injection based on JWT claims
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
data:
  nginx.conf: |
    server {
      location / {
        # Extract tenant from JWT
        set $tenant "";
        if ($http_authorization ~* "Bearer (.*)") {
          set $jwt $1;
          # Decode JWT and extract tenant claim
        }
        
        # Add tenant header
        proxy_set_header X-Grafana-Tenant $tenant;
        proxy_pass http://grafana:3000;
      }
    }
```

**3. Configure Grafana with Template Variables**:

```yaml
datasources:
  - name: Mimir
    type: prometheus
    url: http://mimir:9009/prometheus
    jsonData:
      httpHeaderName1: "X-Scope-OrgID"
    # Use header from auth proxy
    secureJsonFields:
      httpHeaderValue1: "${__header.X-Grafana-Tenant}"
```

### Pros & Cons

**Pros**:

- ✅ True SSO integration with corporate identity provider
- ✅ Tenant context derived from user identity
- ✅ Single Grafana instance with automatic filtering
- ✅ Most secure (no manual datasource selection)
- ✅ Audit trail tied to corporate identity
- ✅ Can support complex RBAC scenarios

**Cons**:

- ❌ Most complex to set up and maintain
- ❌ Requires external authentication infrastructure
- ❌ Need to configure datasource templating
- ❌ Debugging can be challenging
- ❌ Dependent on auth proxy availability

### Best For

- Enterprise environments with existing SSO
- Strict compliance requirements
- Large-scale multi-tenancy (100+ tenants)
- Organizations with dedicated security teams

---

## Comparison Matrix

| Feature                         | Separate Instances          | Organizations | Teams + RBAC           | Auth Proxy  |
| ------------------------------- | --------------------------- | ------------- | ---------------------- | ----------- |
| **Data Isolation**              | Complete                    | Complete      | Good                   | Complete    |
| **Resource Usage**              | High                        | Low           | Low                    | Medium      |
| **Setup Complexity**            | Low                         | Medium        | High                   | Very High   |
| **Operational Overhead**        | High                        | Low           | Medium                 | Medium      |
| **User Management**             | Per-instance                | Centralized   | Centralized            | Centralized |
| **Cross-Tenant View**           | Requires separate instance  | No            | Yes (with permissions) | No          |
| **SSO Integration**             | Per-instance                | Yes           | Yes                    | Native      |
| **Grafana Enterprise Required** | No                          | No            | Yes                    | No          |
| **Dashboard Sharing**           | Manual replication          | Per-org only  | Yes                    | Yes         |
| **Tenant Switching**            | Different URLs              | Login/Logout  | Automatic              | Automatic   |
| **Cost**                        | Higher (multiple instances) | Lower         | Higher (Enterprise)    | Medium      |

---

## Recommendation

### For This POC/Demo Environment

**Current Setup is Fine**: Keep the single Grafana with all datasources visible for platform administrators and demonstrations.

### For Production

Choose based on your requirements:

**1. Strong Isolation Required** → **Separate Grafana Instances**

- Best security posture
- Clearest boundaries
- Worth the operational overhead

**2. Balanced Approach** → **Grafana Organizations**

- Good isolation
- Single instance to manage
- No additional licensing costs

**3. Enterprise Environment** → **Auth Proxy with SSO**

- Best user experience
- Audit and compliance ready
- Requires infrastructure investment

---

## Migration Path

If you decide to implement true multi-tenancy, here's a suggested migration path:

### Phase 1: Add Platform Grafana

Keep current Grafana as platform admin tool:

```bash
# Rename current deployment
kubectl label deployment grafana environment=platform -n monitoring

# Update service
kubectl label service grafana environment=platform -n monitoring
```

### Phase 2: Deploy Tenant Grafanas

Create tenant-specific instances:

```bash
# Apply stage grafana
kubectl apply -k gitops/components/monitoring/grafana/overlays/stage

# Apply prod grafana
kubectl apply -k gitops/components/monitoring/grafana/overlays/prod
```

### Phase 3: Configure Authentication

Set up SSO/LDAP for each Grafana instance based on tenant teams.

### Phase 4: Migrate Dashboards

Export dashboards from platform Grafana and import to tenant Grafanas.

### Phase 5: Update Documentation

Update README and runbooks with new access patterns.

---

## Additional Resources

- [Grafana Organizations Documentation](https://grafana.com/docs/grafana/latest/administration/organization-management/)
- [Grafana Teams Documentation](https://grafana.com/docs/grafana/latest/administration/team-management/)
- [Grafana Authentication Documentation](https://grafana.com/docs/grafana/latest/setup-grafana/configure-security/configure-authentication/)
- [OAuth2-Proxy](https://oauth2-proxy.github.io/oauth2-proxy/)
- [Grafana Provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)
