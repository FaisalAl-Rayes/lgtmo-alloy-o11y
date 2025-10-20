#!/bin/bash
set -e

# Get port from first argument, default to 8282 if not provided
port="${1:-8282}"
app_url="http://localhost:${port}"

echo "Generating traffic to application..."
echo "Target: $app_url"
echo "Press Ctrl+C to stop"
echo ""

counter=0
while true; do
    counter=$((counter + 1))
    
    # Generate regular requests
    curl -s "$app_url/" > /dev/null && echo "[$counter] GET /"
    sleep 0.5
    curl -s "$app_url/api/users" > /dev/null && echo "[$counter] GET /api/users"
    sleep 0.5
    curl -s "$app_url/api/data" > /dev/null && echo "[$counter] GET /api/data"
    sleep 0.5
    
    # Occasionally hit slow endpoint
    if (( counter % 5 == 0 )); then
        curl -s "$app_url/api/slow" > /dev/null && echo "[$counter] GET /api/slow (slow)"
        sleep 1
    fi
    
    # Occasionally hit error endpoint
    if (( counter % 7 == 0 )); then
        curl -s "$app_url/api/error" > /dev/null || echo "[$counter] GET /api/error (error)"
        sleep 0.5
    fi
    
    sleep 2
done

