#!/bin/bash
set -e

# Cleanup function to kill all background jobs when script exits
cleanup() {
    echo ""
    echo "Stopping all port-forwards..."
    kill $(jobs -p) 2>/dev/null || true
    exit 0
}

# Set trap to cleanup on SIGINT (Ctrl+C) and SIGTERM
trap cleanup SIGINT SIGTERM

echo "==========================================="
echo "Port-forwarding all monitoring services..."
echo "==========================================="
echo ""

# Grafana
echo "Starting Grafana port-forward..."
kubectl port-forward -n monitoring service/grafana 3000:3000 --context monitoring-cluster > /dev/null 2>&1 &
echo "  ✓ Grafana: http://localhost:3000"
echo ""

# Tempo
# echo "Starting Tempo port-forwards..."
# kubectl port-forward -n monitoring service/tempo 3200:3200 --context monitoring-cluster > /dev/null 2>&1 &
# kubectl port-forward -n monitoring service/tempo 4317:4317 --context monitoring-cluster > /dev/null 2>&1 &
# kubectl port-forward -n monitoring service/tempo 4318:4318 --context monitoring-cluster > /dev/null 2>&1 &
# echo "  ✓ Tempo HTTP: http://localhost:3200"
# echo "  ✓ Tempo OTLP gRPC: localhost:4317"
# echo "  ✓ Tempo OTLP HTTP: http://localhost:4318"
# echo ""

# Loki
echo "Starting Loki port-forwards..."
kubectl port-forward -n monitoring service/loki 3100:3100 --context monitoring-cluster > /dev/null 2>&1 &
kubectl port-forward -n monitoring service/loki 9096:9095 --context monitoring-cluster > /dev/null 2>&1 &
echo "  ✓ Loki HTTP: http://localhost:3100"
echo "  ✓ Loki gRPC: localhost:9096"
echo ""

# Mimir
# echo "Starting Mimir port-forwards..."
# kubectl port-forward -n monitoring service/mimir 9009:9009 --context monitoring-cluster > /dev/null 2>&1 &
# kubectl port-forward -n monitoring service/mimir 9095:9095 --context monitoring-cluster > /dev/null 2>&1 &
# echo "  ✓ Mimir HTTP: http://localhost:9009"
# echo "  ✓ Mimir gRPC: localhost:9095"
# echo ""

# Minio
# echo "Starting Minio port-forwards..."
# kubectl port-forward -n monitoring service/minio 9000:9000 --context monitoring-cluster > /dev/null 2>&1 &
# kubectl port-forward -n monitoring service/minio 9001:9001 --context monitoring-cluster > /dev/null 2>&1 &
# echo "  ✓ Minio API: http://localhost:9000"
# echo "  ✓ Minio Console: http://localhost:9001"
# echo ""

# Alloy-Alerts
echo "Starting Alloy-Alerts port-forward..."
kubectl port-forward -n alloy-system service/alloy-alerts 12333:12345 --context monitoring-cluster > /dev/null 2>&1 &
echo "  ✓ Alloy-Alerts HTTP/Metrics: http://localhost:12333"
echo ""

echo "==========================================="
echo "All services are being port-forwarded!"
echo "Press Ctrl+C to stop all port-forwards"
echo "==========================================="

# Wait for all background jobs
wait
