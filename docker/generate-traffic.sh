#!/bin/bash

echo "🚦 Generating traffic for Multi-Tenant LGTM+O Stack..."
echo "🏢 Tenant A (ACME Corp) - port 8080"
echo "🏢 Tenant B (Globex Inc) - port 8081"
echo ""
echo "Press Ctrl+C to stop"
echo ""

counter=0

while true; do
  counter=$((counter + 1))
  
  # Tenant A (ACME Corp) - Regular operations
  curl -s http://localhost:8080/api/users > /dev/null 2>&1 &
  sleep 0.3
  
  curl -s http://localhost:8080/api/data > /dev/null 2>&1 &
  sleep 0.3
  
  # Tenant B (Globex Inc) - Regular operations
  curl -s http://localhost:8081/api/users > /dev/null 2>&1 &
  sleep 0.3
  
  curl -s http://localhost:8081/api/data > /dev/null 2>&1 &
  sleep 0.3
  
  # Occasionally call the slow endpoint for Tenant A
  if [ $((counter % 5)) -eq 0 ]; then
    echo "📈 Request #$counter - 🏢 ACME: slow operation"
    curl -s http://localhost:8080/api/slow > /dev/null 2>&1 &
  fi
  
  # Occasionally call the slow endpoint for Tenant B
  if [ $((counter % 7)) -eq 0 ]; then
    echo "📈 Request #$counter - 🏢 Globex: slow operation"
    curl -s http://localhost:8081/api/slow > /dev/null 2>&1 &
  fi
  
  # Occasionally trigger errors for both tenants
  if [ $((counter % 8)) -eq 0 ]; then
    echo "⚠️  Request #$counter - 🏢 ACME: triggering error"
    curl -s http://localhost:8080/api/error > /dev/null 2>&1 &
  fi
  
  if [ $((counter % 10)) -eq 0 ]; then
    echo "⚠️  Request #$counter - 🏢 Globex: triggering error"
    curl -s http://localhost:8081/api/error > /dev/null 2>&1 &
  fi
  
  if [ $((counter % 5)) -ne 0 ] && [ $((counter % 7)) -ne 0 ] && [ $((counter % 8)) -ne 0 ] && [ $((counter % 10)) -ne 0 ]; then
    echo "📊 Request #$counter - Both tenants: regular traffic"
  fi
  
  sleep 2
done

