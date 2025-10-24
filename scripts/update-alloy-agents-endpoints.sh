#!/bin/bash
set -e

# This script generates Alloy agent configurations for all three agents (logs, metrics, traces)
# with the actual monitoring cluster IP
# For clusters running as Docker containers (minikube with Docker driver, Kind, etc.),
# it uses the shared Docker network IP for cross-cluster communication
# The .tmpl files serve as templates with endpoint placeholders
# Run this after starting the clusters

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SHARED_NETWORK="multi-cluster-observability"

echo -e "${GREEN}=== Updating Alloy Agent Endpoints (Logs, Metrics, Traces) ===${NC}"
echo ""

# Check if monitoring-cluster Docker container exists (minikube/Kind)
if docker ps --format '{{.Names}}' | grep -q "^monitoring-cluster$"; then
    echo "Detected Docker-based cluster: monitoring-cluster"
    
    # Ensure shared Docker network exists
    if ! docker network inspect "$SHARED_NETWORK" &> /dev/null; then
        echo -e "${YELLOW}Creating shared Docker network: $SHARED_NETWORK${NC}"
        docker network create "$SHARED_NETWORK"
    fi
    
    # Connect clusters to shared network if not already connected
    for cluster in monitoring-cluster stage-cluster prod-cluster control-cluster; do
        if docker ps --format '{{.Names}}' | grep -q "^${cluster}$"; then
            # Check if already connected
            if ! docker network inspect "$SHARED_NETWORK" --format='{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | grep -q "^${cluster}$"; then
                echo "Connecting ${cluster} to ${SHARED_NETWORK} network..."
                docker network connect "$SHARED_NETWORK" "$cluster" 2>/dev/null || true
            fi
        fi
    done
    
    echo -e "${GREEN}✓ All clusters connected to shared network${NC}"
    echo ""
    
    # Get monitoring cluster IP from shared Docker network
    monitoring_ip=$(docker network inspect "$SHARED_NETWORK" --format='{{range .Containers}}{{if eq .Name "monitoring-cluster"}}{{.IPv4Address}}{{end}}{{end}}' | cut -d'/' -f1)
    
    if [[ -z "$monitoring_ip" ]]; then
        echo -e "${RED}Error: Could not get monitoring-cluster IP from $SHARED_NETWORK network${NC}"
        exit 1
    fi
    
    echo "Using shared network IP: $monitoring_ip"
else
    # Fallback to minikube IP command for non-Docker based clusters
    monitoring_ip=$(minikube ip -p monitoring-cluster 2>/dev/null)
    
    if [[ -z "$monitoring_ip" ]]; then
        echo -e "${RED}Error: monitoring-cluster is not running${NC}"
        exit 1
    fi
    
    echo "Using minikube IP: $monitoring_ip"
fi

echo ""
echo -e "${YELLOW}Generating Alloy agent configurations with monitoring cluster IP: $monitoring_ip${NC}"
echo ""

# Define port mappings for each environment
# Stage environment ports
STAGE_LOKI_PORT="30100"
STAGE_MIMIR_PORT="30090"
STAGE_TEMPO_PORT="30200"

# Prod environment ports
PROD_LOKI_PORT="30101"
PROD_MIMIR_PORT="30091"
PROD_TEMPO_PORT="30201"

# Function to generate config from template
generate_config() {
    local template="$1"
    local output="$2"
    local loki_endpoint="$3"
    local mimir_endpoint="$4"
    local tempo_endpoint="$5"
    
    if [[ ! -f "$template" ]]; then
        echo -e "${RED}Error: Template file $template not found${NC}"
        return 1
    fi
    
    sed -e "s|LOKI_ENDPOINT_PLACEHOLDER|${loki_endpoint}|g" \
        -e "s|MIMIR_ENDPOINT_PLACEHOLDER|${mimir_endpoint}|g" \
        -e "s|TEMPO_ENDPOINT_PLACEHOLDER|${tempo_endpoint}|g" \
        "$template" > "$output"
    
    echo -e "  ${GREEN}✓${NC} Generated: $output"
}

echo -e "${YELLOW}Updating alloy-logs configurations...${NC}"
# Generate alloy-logs stage overlay from template
generate_config \
    "gitops/components/alloy-logs/overlays/stage/env-patch.yaml.tmpl" \
    "gitops/components/alloy-logs/overlays/stage/env-patch.yaml" \
    "${monitoring_ip}:${STAGE_LOKI_PORT}" \
    "" \
    ""

# Generate alloy-logs prod overlay from template
generate_config \
    "gitops/components/alloy-logs/overlays/prod/env-patch.yaml.tmpl" \
    "gitops/components/alloy-logs/overlays/prod/env-patch.yaml" \
    "${monitoring_ip}:${PROD_LOKI_PORT}" \
    "" \
    ""

echo ""
echo -e "${YELLOW}Updating alloy-metrics configurations...${NC}"
# Generate alloy-metrics stage overlay from template
generate_config \
    "gitops/components/alloy-metrics/overlays/stage/env-patch.yaml.tmpl" \
    "gitops/components/alloy-metrics/overlays/stage/env-patch.yaml" \
    "" \
    "${monitoring_ip}:${STAGE_MIMIR_PORT}" \
    ""

# Generate alloy-metrics prod overlay from template
generate_config \
    "gitops/components/alloy-metrics/overlays/prod/env-patch.yaml.tmpl" \
    "gitops/components/alloy-metrics/overlays/prod/env-patch.yaml" \
    "" \
    "${monitoring_ip}:${PROD_MIMIR_PORT}" \
    ""

echo ""
echo -e "${YELLOW}Updating alloy-traces configurations...${NC}"
# Generate alloy-traces stage overlay from template
generate_config \
    "gitops/components/alloy-traces/overlays/stage/env-patch.yaml.tmpl" \
    "gitops/components/alloy-traces/overlays/stage/env-patch.yaml" \
    "" \
    "" \
    "${monitoring_ip}:${STAGE_TEMPO_PORT}"

# Generate alloy-traces prod overlay from template
generate_config \
    "gitops/components/alloy-traces/overlays/prod/env-patch.yaml.tmpl" \
    "gitops/components/alloy-traces/overlays/prod/env-patch.yaml" \
    "" \
    "" \
    "${monitoring_ip}:${PROD_TEMPO_PORT}"

echo ""
echo -e "${GREEN}✓ All configurations generated successfully!${NC}"
echo ""
echo "Next steps:"
echo "  1. Commit and push these changes for GitOps, or"
echo "  2. Apply them directly:"
echo ""
echo "     # Stage cluster"
echo "     kubectl apply -k gitops/components/alloy-logs/overlays/stage --context stage-cluster"
echo "     kubectl apply -k gitops/components/alloy-metrics/overlays/stage --context stage-cluster"
echo "     kubectl apply -k gitops/components/alloy-traces/overlays/stage --context stage-cluster"
echo ""
echo "     # Prod cluster"
echo "     kubectl apply -k gitops/components/alloy-logs/overlays/prod --context prod-cluster"
echo "     kubectl apply -k gitops/components/alloy-metrics/overlays/prod --context prod-cluster"
echo "     kubectl apply -k gitops/components/alloy-traces/overlays/prod --context prod-cluster"
echo ""
echo "Docker network details:"
docker network inspect "$SHARED_NETWORK" --format='{{range .Containers}}  {{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}' 2>/dev/null || true
echo ""
echo -e "${GREEN}Endpoint configuration:${NC}"
echo "  Stage:"
echo "    Loki:  ${monitoring_ip}:${STAGE_LOKI_PORT}"
echo "    Mimir: ${monitoring_ip}:${STAGE_MIMIR_PORT}"
echo "    Tempo: ${monitoring_ip}:${STAGE_TEMPO_PORT}"
echo "  Prod:"
echo "    Loki:  ${monitoring_ip}:${PROD_LOKI_PORT}"
echo "    Mimir: ${monitoring_ip}:${PROD_MIMIR_PORT}"
echo "    Tempo: ${monitoring_ip}:${PROD_TEMPO_PORT}"

