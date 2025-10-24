#!/bin/bash
set -e

# This script generates Alloy agent configurations with the actual monitoring cluster IP
# For clusters running as Docker containers (minikube with Docker driver, Kind, etc.),
# it uses the shared Docker network IP for cross-cluster communication
# The .tmpl files serve as templates with MONITORING_CLUSTER_IP placeholder
# Run this after starting the clusters

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SHARED_NETWORK="multi-cluster-observability"

echo -e "${GREEN}=== Updating Alloy Endpoints ===${NC}"
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

# Generate stage overlay from template
stage_template="gitops/components/alloy-agent/overlays/stage/env-patch.yaml.tmpl"
stage_patch="gitops/components/alloy-agent/overlays/stage/env-patch.yaml"

if [[ ! -f "$stage_template" ]]; then
    echo "Error: Template file $stage_template not found"
    exit 1
fi

sed "s/MONITORING_CLUSTER_IP/$monitoring_ip/g" "$stage_template" > "$stage_patch"
echo "Generated: $stage_patch (from template)"

# Generate prod overlay from template
prod_template="gitops/components/alloy-agent/overlays/prod/env-patch.yaml.tmpl"
prod_patch="gitops/components/alloy-agent/overlays/prod/env-patch.yaml"

if [[ ! -f "$prod_template" ]]; then
    echo "Error: Template file $prod_template not found"
    exit 1
fi

sed "s/MONITORING_CLUSTER_IP/$monitoring_ip/g" "$prod_template" > "$prod_patch"
echo "Generated: $prod_patch (from template)"

echo ""
echo -e "${GREEN}✓ Configuration generated!${NC}"
echo ""
echo "Next steps:"
echo "  1. Commit and push these changes for GitOps, or"
echo "  2. Apply them directly:"
echo "     kubectl apply -k gitops/components/alloy-agent/overlays/stage --context stage-cluster"
echo "     kubectl apply -k gitops/components/alloy-agent/overlays/prod --context prod-cluster"
echo ""
echo "Docker network details:"
docker network inspect "$SHARED_NETWORK" --format='{{range .Containers}}  {{.Name}}: {{.IPv4Address}}{{"\n"}}{{end}}' 2>/dev/null || true

