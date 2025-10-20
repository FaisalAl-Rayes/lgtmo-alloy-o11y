#!/bin/bash
set -e

echo "=========================================="
echo "Setting up /etc/hosts for Ingress Access"
echo "=========================================="
echo ""

# Get cluster IPs
monitoring_ip=$(minikube ip -p monitoring-cluster 2>/dev/null)
stage_ip=$(minikube ip -p stage-cluster 2>/dev/null)
prod_ip=$(minikube ip -p prod-cluster 2>/dev/null)

if [[ -z "$monitoring_ip" ]] || [[ -z "$stage_ip" ]] || [[ -z "$prod_ip" ]]; then
    echo "Error: One or more clusters are not running"
    echo "Run './.hack/clusters-up.sh' first"
    exit 1
fi

echo "Cluster IPs:"
echo "  Monitoring: $monitoring_ip"
echo "  Stage:      $stage_ip"
echo "  Prod:       $prod_ip"
echo ""

# Create temporary hosts entries
HOSTS_ENTRIES="
# Multi-cluster Observability - Ingress Hosts
$monitoring_ip grafana.monitoring.local
$stage_ip app.stage.local
$prod_ip app.prod.local
"

echo "The following entries need to be added to /etc/hosts:"
echo "$HOSTS_ENTRIES"
echo ""

# Check if running on macOS or Linux
if [[ "$(uname)" == "Darwin" ]] || [[ "$(uname)" == "Linux" ]]; then
    echo "Would you like to add these entries to /etc/hosts? (requires sudo)"
    echo "Type 'yes' to continue, or 'no' to see manual instructions:"
    read -r response
    
    if [[ "$response" == "yes" ]]; then
        # Remove old entries if they exist
        sudo sed -i.bak '/# Multi-cluster Observability - Ingress Hosts/,/app.prod.local/d' /etc/hosts
        
        # Add new entries
        echo "$HOSTS_ENTRIES" | sudo tee -a /etc/hosts > /dev/null
        
        echo ""
        echo "✅ Successfully added entries to /etc/hosts"
        echo ""
        echo "You can now access:"
        echo "  Grafana:    http://grafana.monitoring.local"
        echo "  Stage App:  http://app.stage.local"
        echo "  Prod App:   http://app.prod.local"
        echo ""
    else
        echo ""
        echo "To add these entries manually, run:"
        echo "  sudo nano /etc/hosts"
        echo ""
        echo "Then add these lines at the end:"
        echo "$HOSTS_ENTRIES"
        echo ""
    fi
else
    echo "Unsupported OS. Please manually add the entries above to your hosts file."
fi

echo "=========================================="

