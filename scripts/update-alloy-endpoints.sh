#!/bin/bash
set -e

# This script generates Alloy agent configurations from templates with the actual monitoring cluster IP
# The .tmpl files serve as templates with MONITORING_CLUSTER_IP placeholder
# Run this after starting the clusters

monitoring_ip=$(minikube ip -p monitoring-cluster)

if [[ -z "$monitoring_ip" ]]; then
    echo "Error: monitoring-cluster is not running"
    exit 1
fi

echo "Generating Alloy agent configurations with monitoring cluster IP: $monitoring_ip"
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
echo "Configuration generated! Commit and push these changes, or apply them directly:"
echo "  kubectl apply -k gitops/components/alloy-agent/overlays/stage --context stage-cluster"
echo "  kubectl apply -k gitops/components/alloy-agent/overlays/prod --context prod-cluster"

