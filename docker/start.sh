#!/bin/bash

echo "🚀 Starting LGTM+O Stack..."
echo ""

# Start all services
docker compose up -d

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 10

# Check service health
echo ""
echo "📊 Service Status:"
docker compose ps

echo ""
echo "✅ LGTM+O Stack is starting up!"
echo ""
echo "🌐 Access the following URLs:"
echo "   - Grafana:    http://localhost:3000"
echo "   - Prometheus: http://localhost:9090"
echo "   - Demo App:   http://localhost:8080"
echo ""
echo "📖 Try these demo app endpoints:"
echo "   curl http://localhost:8080/api/users"
echo "   curl http://localhost:8080/api/data"
echo "   curl http://localhost:8080/api/slow"
echo ""
echo "🔍 View logs:"
echo "   docker compose logs -f [service-name]"
echo ""
echo "🛑 Stop the stack:"
echo "   docker compose down"

