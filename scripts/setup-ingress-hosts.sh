#!/usr/bin/env bash

set -e

echo "=========================================="
echo "Setting up /etc/hosts for Ingress Access"
echo "=========================================="

# Get minikube IPs
MONITORING_IP=$(minikube ip -p monitoring-cluster 2>/dev/null || echo "")
STAGE_IP=$(minikube ip -p stage-cluster 2>/dev/null || echo "")
PROD_IP=$(minikube ip -p prod-cluster 2>/dev/null || echo "")

# Check if clusters are running
if [[ -z "$MONITORING_IP" ]] || [[ -z "$STAGE_IP" ]] || [[ -z "$PROD_IP" ]]; then
    echo "❌ Error: One or more clusters are not running."
    echo "Please start the clusters first with: ./.hack/clusters-up.sh"
    exit 1
fi

# Detect OS
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "Detected macOS - using minikube IPs with NodePorts"
    MONITORING_HOST="${MONITORING_IP}"
    STAGE_HOST="${STAGE_IP}"
    PROD_HOST="${PROD_IP}"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    echo "Detected Linux - using minikube IPs directly"
    MONITORING_HOST="${MONITORING_IP}"
    STAGE_HOST="${STAGE_IP}"
    PROD_HOST="${PROD_IP}"
else
    echo "❌ Unsupported OS: $OSTYPE"
    exit 1
fi

# Check if entries already exist
HOSTS_FILE="/etc/hosts"
MARKER="# Multi-cluster Observability - Ingress Hosts"

if grep -q "$MARKER" "$HOSTS_FILE" 2>/dev/null; then
    echo "⚠️  Entries already exist in /etc/hosts"
    echo "Removing old entries..."
    
    # Remove old entries (requires sudo)
    sudo sed -i.bak "/$MARKER/,/^$/d" "$HOSTS_FILE" 2>/dev/null || \
    sudo sed -i '' "/$MARKER/,/^$/d" "$HOSTS_FILE" 2>/dev/null
fi

# Prepare new entries
NEW_ENTRIES="$MARKER
$MONITORING_HOST grafana.monitoring.local
$STAGE_HOST app.stage.local
$PROD_HOST app.prod.local
"

echo ""
echo "The following entries need to be added to /etc/hosts:"
echo "$NEW_ENTRIES"

# Add entries
echo ""
echo "Would you like to add these entries to /etc/hosts? (requires sudo)"
echo "Type 'yes' to continue, or 'no' to see manual instructions:"
read -r response

if [[ "$response" == "yes" ]]; then
    echo "$NEW_ENTRIES" | sudo tee -a "$HOSTS_FILE" > /dev/null
    echo ""
    echo "✅ Successfully added entries to /etc/hosts"
    echo ""
    echo "You can now access:"
    echo "  Grafana:    http://grafana.monitoring.local:30079"
    echo "  Stage App:  http://app.stage.local:30080"
    echo "  Prod App:   http://app.prod.local:30081"
else
    echo ""
    echo "Manual instructions:"
    echo "1. Open /etc/hosts with your editor:"
    echo "   sudo nano /etc/hosts"
    echo ""
    echo "2. Add these lines at the end:"
    echo "$NEW_ENTRIES"
    echo ""
    echo "3. Save and exit"
    echo ""
    echo "4. Access services at:"
    echo "   Grafana:    http://grafana.monitoring.local:30079"
    echo "   Stage App:  http://app.stage.local:30080"
    echo "   Prod App:   http://app.prod.local:30081"
fi

echo "=========================================="
