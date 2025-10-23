#!/bin/bash

# Load Alert Rules to Mimir and Loki
# This script loads alerting rules to the respective backends

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="monitoring"
TENANT_ID="${TENANT_ID:-tenant-a}"
MIMIR_URL="${MIMIR_URL:-http://localhost:9009}"
LOKI_URL="${LOKI_URL:-http://localhost:3100}"

echo -e "${GREEN}=== Loading Alert Rules ===${NC}"
echo "Namespace: $NAMESPACE"
echo "Tenant ID: $TENANT_ID"
echo ""

# Function to load rules to Mimir
load_mimir_rules() {
    local rules_file=$1
    local namespace=$2
    
    echo -e "${YELLOW}Loading metrics rules to Mimir...${NC}"
    
    # Extract YAML content from ConfigMap
    kubectl get configmap mimir-rules-metrics -n $NAMESPACE -o jsonpath='{.data.metrics-alerts\.yaml}' > /tmp/metrics-rules.yaml
    
    # Load to Mimir ruler API
    curl -X POST \
        -H "Content-Type: application/yaml" \
        -H "X-Scope-OrgID: $TENANT_ID" \
        --data-binary @/tmp/metrics-rules.yaml \
        "$MIMIR_URL/prometheus/config/v1/rules/$namespace"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Metrics rules loaded successfully${NC}"
    else
        echo -e "${RED}✗ Failed to load metrics rules${NC}"
        exit 1
    fi
}

# Function to load rules to Loki
load_loki_rules() {
    local rules_file=$1
    local namespace=$2
    
    echo -e "${YELLOW}Loading log rules to Loki...${NC}"
    
    # Extract YAML content from ConfigMap
    kubectl get configmap loki-rules-logs -n $NAMESPACE -o jsonpath='{.data.logs-alerts\.yaml}' > /tmp/logs-rules.yaml
    
    # Load to Loki ruler API
    curl -X POST \
        -H "Content-Type: application/yaml" \
        -H "X-Scope-OrgID: $TENANT_ID" \
        --data-binary @/tmp/logs-rules.yaml \
        "$LOKI_URL/loki/api/v1/rules/$namespace"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Log rules loaded successfully${NC}"
    else
        echo -e "${RED}✗ Failed to load log rules${NC}"
        exit 1
    fi
}

# Function to verify rules are loaded
verify_rules() {
    echo -e "${YELLOW}Verifying rules...${NC}"
    echo ""
    
    echo "Mimir rules:"
    curl -s -H "X-Scope-OrgID: $TENANT_ID" "$MIMIR_URL/prometheus/api/v1/rules" | jq '.data.groups[] | {name: .name, rules: .rules | length}'
    
    echo ""
    echo "Loki rules:"
    curl -s -H "X-Scope-OrgID: $TENANT_ID" "$LOKI_URL/loki/api/v1/rules" | jq '.data.groups[] | {name: .name, rules: .rules | length}'
}

# Main execution
echo -e "${YELLOW}Step 1: Applying ConfigMaps...${NC}"
kubectl apply -f ../o11y/alerting-rules/base/metrics-rules.yaml
kubectl apply -f ../o11y/alerting-rules/base/logs-rules.yaml

echo ""
echo -e "${YELLOW}Step 2: Port-forwarding services (if needed)...${NC}"
echo "If running in Kubernetes, port-forward the services:"
echo "  kubectl port-forward -n $NAMESPACE svc/mimir 9009:9009 &"
echo "  kubectl port-forward -n $NAMESPACE svc/loki 3100:3100 &"
echo ""

read -p "Press enter to continue once port-forwarding is ready (or if using NodePort/Ingress)..."

echo ""
echo -e "${YELLOW}Step 3: Loading rules...${NC}"
load_mimir_rules "metrics-rules" "default"
echo ""
load_loki_rules "logs-rules" "default"

echo ""
echo -e "${YELLOW}Step 4: Verifying rules...${NC}"
verify_rules

echo ""
echo -e "${GREEN}=== Done! ===${NC}"
echo ""
echo "To view alerts in Alertmanager:"
echo "  kubectl port-forward -n $NAMESPACE svc/alertmanager 9093:9093"
echo "  Open http://localhost:9093"
echo ""
echo "To view active alerts in Mimir:"
echo "  curl -H 'X-Scope-OrgID: $TENANT_ID' $MIMIR_URL/prometheus/api/v1/alerts"
echo ""
echo "To view active alerts in Loki:"
echo "  curl -H 'X-Scope-OrgID: $TENANT_ID' $LOKI_URL/loki/api/v1/rules/alerts"

# Cleanup temp files
rm -f /tmp/metrics-rules.yaml /tmp/logs-rules.yaml

