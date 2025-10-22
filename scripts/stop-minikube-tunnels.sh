#!/usr/bin/env bash

set -e

LOG_DIR="/tmp/minikube-tunnels"

echo "=========================================="
echo "Stopping Minikube Tunnels"
echo "=========================================="
echo ""

# Function to stop tunnel
stop_tunnel() {
    local cluster=$1
    local pid_file="$LOG_DIR/${cluster}.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "Stopping $cluster tunnel (PID: $pid)..."
            kill "$pid" 2>/dev/null || true
            rm -f "$pid_file"
        else
            echo "⚠️  $cluster tunnel (PID: $pid) is not running"
            rm -f "$pid_file"
        fi
    else
        echo "⚠️  No PID file found for $cluster"
    fi
}

stop_tunnel "monitoring-cluster"
stop_tunnel "stage-cluster"
stop_tunnel "prod-cluster"

# Also try to kill any remaining minikube tunnel processes
echo ""
echo "Cleaning up any remaining minikube tunnel processes..."
pkill -f "minikube tunnel" 2>/dev/null || true

echo ""
echo "✅ All tunnels stopped"
echo "=========================================="

