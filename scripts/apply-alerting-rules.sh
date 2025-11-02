#!/bin/bash

# Script to apply alerting rules for all tenants
# Applies PrometheusRule resources for stage and prod environments

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ALERTS_DIR="${PROJECT_ROOT}/o11y/alerting-rules/tenants"

echo "🚀 Applying alerting rules for all tenants..."
echo "================================================"

# Apply stage alerts
echo ""
echo "📋 Applying Stage environment alerts..."
kubectl apply --context monitoring-cluster -f "${ALERTS_DIR}/stage/app-alerts-stage.yaml"
kubectl apply --context monitoring-cluster -f "${ALERTS_DIR}/stage/log-alerts-stage.yaml"

# Apply prod alerts
echo ""
echo "📋 Applying Prod environment alerts..."
kubectl apply --context monitoring-cluster -f "${ALERTS_DIR}/prod/app-alerts-prod.yaml"
kubectl apply --context monitoring-cluster -f "${ALERTS_DIR}/prod/log-alerts-prod.yaml"

echo ""
echo "✅ All alerting rules applied successfully!"

