#!/bin/bash
set -e

echo "Port-forwarding Grafana to localhost:3000..."
echo "Access Grafana at: http://localhost:3000"
echo "Press Ctrl+C to stop port-forwarding"
echo ""

kubectl port-forward -n monitoring service/grafana 3000:3000 --context monitoring-cluster

