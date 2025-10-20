#!/bin/bash
set -e

echo "=========================================="
echo "Multi-Cluster Observability - Cluster Info"
echo "=========================================="
echo ""

# Get cluster IPs
echo "Cluster IPs:"
echo "------------"
control_ip=$(minikube ip -p control-cluster 2>/dev/null || echo "Not running")
stage_ip=$(minikube ip -p stage-cluster 2>/dev/null || echo "Not running")
prod_ip=$(minikube ip -p prod-cluster 2>/dev/null || echo "Not running")
monitoring_ip=$(minikube ip -p monitoring-cluster 2>/dev/null || echo "Not running")

echo "control-cluster:     $control_ip"
echo "stage-cluster:       $stage_ip"
echo "prod-cluster:        $prod_ip"
echo "monitoring-cluster:  $monitoring_ip"
echo ""

# Service URLs
echo "Service URLs:"
echo "-------------"
if [[ "$monitoring_ip" != "Not running" ]]; then
    echo "Grafana:             http://$monitoring_ip:30300"
    echo "Mimir Stage:         http://$monitoring_ip:30090"
    echo "Mimir Prod:          http://$monitoring_ip:30091"
    echo "Loki Stage:          http://$monitoring_ip:30100"
    echo "Loki Prod:           http://$monitoring_ip:30101"
    echo "Tempo Stage:         http://$monitoring_ip:30200"
    echo "Tempo Prod:          http://$monitoring_ip:30201"
else
    echo "monitoring-cluster is not running"
fi
echo ""

if [[ "$stage_ip" != "Not running" ]]; then
    echo "App Stage:           http://$stage_ip:30800"
else
    echo "stage-cluster is not running"
fi

if [[ "$prod_ip" != "Not running" ]]; then
    echo "App Prod:            http://$prod_ip:30800"
else
    echo "prod-cluster is not running"
fi
echo ""

# Cluster Status
echo "Cluster Status:"
echo "---------------"
minikube status -p control-cluster 2>/dev/null | grep -E "host:|kubelet:|apiserver:" || echo "control-cluster: Not running"
echo ""
minikube status -p stage-cluster 2>/dev/null | grep -E "host:|kubelet:|apiserver:" || echo "stage-cluster: Not running"
echo ""
minikube status -p prod-cluster 2>/dev/null | grep -E "host:|kubelet:|apiserver:" || echo "prod-cluster: Not running"
echo ""
minikube status -p monitoring-cluster 2>/dev/null | grep -E "host:|kubelet:|apiserver:" || echo "monitoring-cluster: Not running"
echo ""

echo "=========================================="

