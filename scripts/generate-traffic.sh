#!/bin/bash
set -e

# Get cluster IPs
stage_ip=$(minikube ip -p stage-cluster 2>/dev/null)
prod_ip=$(minikube ip -p prod-cluster 2>/dev/null)

if [[ -z "$stage_ip" ]] || [[ -z "$prod_ip" ]]; then
    echo "Error: One or more clusters are not running"
    echo "Run './hack/clusters-up.sh' first"
    exit 1
fi

stage_url="http://$stage_ip:30800"
prod_url="http://$prod_ip:30800"

echo "Generating traffic to instrumented applications..."
echo "Stage App: $stage_url"
echo "Prod App:  $prod_url"
echo "Press Ctrl+C to stop"
echo ""

counter=0
while true; do
    counter=$((counter + 1))
    
    # Generate requests to stage
    curl -s "$stage_url/" > /dev/null && echo "[$counter] Stage: /"
    sleep 0.5
    curl -s "$stage_url/api/users" > /dev/null && echo "[$counter] Stage: /api/users"
    sleep 0.5
    curl -s "$stage_url/api/data" > /dev/null && echo "[$counter] Stage: /api/data"
    sleep 0.5
    
    # Occasionally hit slow endpoint
    if (( counter % 5 == 0 )); then
        curl -s "$stage_url/api/slow" > /dev/null && echo "[$counter] Stage: /api/slow (slow)"
        sleep 1
    fi
    
    # Occasionally hit error endpoint
    if (( counter % 7 == 0 )); then
        curl -s "$stage_url/api/error" > /dev/null || echo "[$counter] Stage: /api/error (error)"
        sleep 0.5
    fi
    
    # Generate requests to prod
    curl -s "$prod_url/" > /dev/null && echo "[$counter] Prod: /"
    sleep 0.5
    curl -s "$prod_url/api/users" > /dev/null && echo "[$counter] Prod: /api/users"
    sleep 0.5
    curl -s "$prod_url/api/data" > /dev/null && echo "[$counter] Prod: /api/data"
    sleep 1
    
    # Occasionally hit slow endpoint
    if (( counter % 6 == 0 )); then
        curl -s "$prod_url/api/slow" > /dev/null && echo "[$counter] Prod: /api/slow (slow)"
        sleep 1
    fi
    
    # Occasionally hit error endpoint
    if (( counter % 10 == 0 )); then
        curl -s "$prod_url/api/error" > /dev/null || echo "[$counter] Prod: /api/error (error)"
        sleep 0.5
    fi
    
    sleep 2
done

