#!/bin/bash
set -e

# This script updates the Alloy agent configurations with the actual monitoring cluster IP
# Run this after starting the clusters

monitoring_ip=$(minikube ip -p monitoring-cluster)

if [[ -z "$monitoring_ip" ]]; then
    echo "Error: monitoring-cluster is not running"
    exit 1
fi

echo "Updating Alloy agent configurations with monitoring cluster IP: $monitoring_ip"
echo ""

# Update stage overlay
stage_patch="gitops/components/alloy-agent/overlays/stage/env-patch.yaml"
sed -i.bak "s/MONITORING_CLUSTER_IP:[0-9]\+/$monitoring_ip:30090/g; s/MONITORING_CLUSTER_IP:[0-9]\+/$monitoring_ip:30100/g; s/MONITORING_CLUSTER_IP:[0-9]\+/$monitoring_ip:30200/g" "$stage_patch"
echo "Updated: $stage_patch"

# Update prod overlay  
prod_patch="gitops/components/alloy-agent/overlays/prod/env-patch.yaml"
sed -i.bak "s/MONITORING_CLUSTER_IP:[0-9]\+/$monitoring_ip:30091/g; s/MONITORING_CLUSTER_IP:[0-9]\+/$monitoring_ip:30101/g; s/MONITORING_CLUSTER_IP:[0-9]\+/$monitoring_ip:30201/g" "$prod_patch"
echo "Updated: $prod_patch"

echo ""
echo "Configuration updated! Commit and push these changes, or apply them directly:"
echo "  kubectl apply -k gitops/components/alloy-agent/overlays/stage --context stage-cluster"
echo "  kubectl apply -k gitops/components/alloy-agent/overlays/prod --context prod-cluster"

