#!/usr/bin/env bash

set -e

echo "=========================================="
echo "Starting Minikube Tunnels"
echo "=========================================="
echo ""
echo "This will start minikube tunnel for each cluster to expose Ingress controllers."
echo "You'll need to enter your password (sudo required for privileged ports)."
echo ""

# Check if clusters are running
for cluster in monitoring-cluster stage-cluster prod-cluster; do
    if ! minikube status -p "$cluster" &>/dev/null; then
        echo "❌ Error: $cluster is not running"
        echo "Please start clusters first with: ./.hack/clusters-up.sh"
        exit 1
    fi
done

# Create log directory
LOG_DIR="/tmp/minikube-tunnels"
mkdir -p "$LOG_DIR"

# Function to start tunnel
start_tunnel() {
    local cluster=$1
    local log_file="$LOG_DIR/${cluster}.log"
    
    echo "Starting tunnel for $cluster..."
    nohup minikube tunnel -p "$cluster" > "$log_file" 2>&1 &
    local pid=$!
    echo "  PID: $pid"
    echo "$pid" > "$LOG_DIR/${cluster}.pid"
    
    # Give it a moment to start
    sleep 1
}

echo "Starting tunnels in the background..."
echo ""

start_tunnel "monitoring-cluster"
start_tunnel "stage-cluster"
start_tunnel "prod-cluster"

echo ""
echo "=========================================="
echo "Tunnels started successfully!"
echo "=========================================="
echo ""

# Read PIDs
MONITORING_PID=$(cat "$LOG_DIR/monitoring-cluster.pid" 2>/dev/null || echo "unknown")
STAGE_PID=$(cat "$LOG_DIR/stage-cluster.pid" 2>/dev/null || echo "unknown")
PROD_PID=$(cat "$LOG_DIR/prod-cluster.pid" 2>/dev/null || echo "unknown")

echo "Tunnel PIDs:"
echo "  Monitoring: $MONITORING_PID"
echo "  Stage:      $STAGE_PID"
echo "  Prod:       $PROD_PID"
echo ""

echo "You can now access services at:"
echo "  Grafana:    http://grafana.monitoring.local:30079"
echo "  Stage App:  http://app.stage.local:30080"
echo "  Prod App:   http://app.prod.local:30081"
echo ""

echo "To stop the tunnels, run:"
echo "  kill $MONITORING_PID $STAGE_PID $PROD_PID"
echo ""
echo "Or use the stop script:"
echo "  ./scripts/stop-minikube-tunnels.sh"
echo ""

echo "Logs are available at:"
echo "  $LOG_DIR/monitoring-cluster.log"
echo "  $LOG_DIR/stage-cluster.log"
echo "  $LOG_DIR/prod-cluster.log"
echo ""
echo "=========================================="
echo ""
echo "💡 Tip: Run './scripts/setup-ingress-hosts.sh' if you haven't already"
echo "    to configure /etc/hosts for friendly hostnames."
echo ""

