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
echo "Port-forwarding STAGE cluster services..."
echo "==========================================="
echo ""

# Full OTEL Instrumented App
echo "Starting full-otel-instrumented-app port-forward..."
kubectl port-forward -n full-otel-instrumented-app-ns service/full-otel-instrumented-app 8080:8080 --context stage-cluster > /dev/null 2>&1 &
echo "  ✓ Full OTEL App: http://localhost:8080"
echo ""

# Prom OTEL Instrumented App
echo "Starting prom-otel-instrumented-app port-forward..."
kubectl port-forward -n prom-otel-instrumented-app-ns service/prom-otel-instrumented-app 8081:8080 --context stage-cluster > /dev/null 2>&1 &
echo "  ✓ Prom OTEL App: http://localhost:8081"
echo ""

# Alloy Logs Agent
echo "Starting Alloy Logs port-forwards..."
kubectl port-forward -n alloy-system service/alloy-logs 12111:12345 --context stage-cluster > /dev/null 2>&1 &
echo "  ✓ Alloy Logs HTTP/Metrics: http://localhost:12111"
echo ""

# Alloy Metrics Agent
echo "Starting Alloy Metrics port-forwards..."
kubectl port-forward -n alloy-system service/alloy-metrics 12222:12345 --context stage-cluster > /dev/null 2>&1 &
echo "  ✓ Alloy Metrics HTTP/Metrics: http://localhost:12222"
echo ""

# Alloy Traces Agent
echo "Starting Alloy Traces port-forwards..."
kubectl port-forward -n alloy-system service/alloy-traces 12333:12345 --context stage-cluster > /dev/null 2>&1 &
echo "  ✓ Alloy Traces HTTP/Metrics: http://localhost:12333"
echo ""

echo "==========================================="
echo "All STAGE services are being port-forwarded!"
echo "Press Ctrl+C to stop all port-forwards"
echo "==========================================="

# Wait for all background jobs
wait

