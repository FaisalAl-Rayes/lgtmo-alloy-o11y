import os
import time
import random
import logging
from flask import Flask, jsonify, request, Response
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.sdk.resources import Resource
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST, REGISTRY

# Configure OpenTelemetry Resource for tracing
resource = Resource.create({
    "service.name": os.getenv("OTEL_SERVICE_NAME", "instrumented-app"),
    "service.version": "1.0.0",
    "deployment.environment": os.getenv("ENVIRONMENT", "unknown"),
    "service.namespace": os.getenv("NAMESPACE", "default")
})

# Get traces endpoint from environment
traces_endpoint = os.getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT",
                            os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://alloy-traces.alloy-system.svc.cluster.local:4317"))

# Setup standard Python logging (stdout/stderr only)
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Setup Tracing with OpenTelemetry
trace.set_tracer_provider(TracerProvider(resource=resource))
tracer_provider = trace.get_tracer_provider()
otlp_exporter = OTLPSpanExporter(
    endpoint=traces_endpoint,
    insecure=True
)
span_processor = BatchSpanProcessor(otlp_exporter)
tracer_provider.add_span_processor(span_processor)

# Setup Prometheus Metrics
request_counter = Counter(
    'app_requests_total',
    'Total number of requests',
    ['endpoint', 'method']
)

request_duration = Histogram(
    'app_request_duration_seconds',
    'Request duration in seconds',
    ['endpoint']
)

error_counter = Counter(
    'app_errors_total',
    'Total number of errors',
    ['type', 'endpoint']
)

# Create Flask app
app = Flask(__name__)

# Instrument Flask with OpenTelemetry
FlaskInstrumentor().instrument_app(app)

# Get tracer
tracer = trace.get_tracer(__name__)

# Prometheus metrics endpoint
@app.route('/metrics')
def metrics():
    return Response(generate_latest(REGISTRY), mimetype=CONTENT_TYPE_LATEST)

@app.route('/')
def home():
    with tracer.start_as_current_span("home") as span:
        span.set_attribute("http.route", "/")
        logger.info("Home endpoint accessed")
        request_counter.labels(endpoint="/", method="GET").inc()
        
        return jsonify({
            "message": "Multi-Cluster Observability Demo Application",
            "environment": os.getenv("ENVIRONMENT", "unknown"),
            "service": os.getenv("OTEL_SERVICE_NAME", "instrumented-app"),
            "endpoints": [
                "/",
                "/api/users",
                "/api/data",
                "/api/slow",
                "/api/error",
                "/health",
                "/metrics"
            ]
        })

@app.route('/api/users')
def get_users():
    start_time = time.time()
    with tracer.start_as_current_span("get_users") as span:
        span.set_attribute("http.route", "/api/users")
        span.set_attribute("http.method", "GET")
        
        # Simulate database query
        with tracer.start_as_current_span("db.query") as db_span:
            db_span.set_attribute("db.system", "postgresql")
            db_span.set_attribute("db.name", "userdb")
            db_span.set_attribute("db.statement", "SELECT * FROM users WHERE active = true")
            db_span.set_attribute("db.operation", "SELECT")
            time.sleep(random.uniform(0.02, 0.08))
            
            users = [
                {"id": 1, "name": "Alice", "email": "alice@example.com"},
                {"id": 2, "name": "Bob", "email": "bob@example.com"},
                {"id": 3, "name": "Charlie", "email": "charlie@example.com"}
            ]
            
            db_span.set_attribute("db.rows_returned", len(users))
            logger.info(f"Retrieved {len(users)} users from database")
        
        span.set_attribute("user.count", len(users))
        request_counter.labels(endpoint="/api/users", method="GET").inc()
        duration = time.time() - start_time
        request_duration.labels(endpoint="/api/users").observe(duration)
        
        return jsonify(users)

@app.route('/api/data')
def get_data():
    start_time = time.time()
    with tracer.start_as_current_span("get_data") as span:
        span.set_attribute("http.route", "/api/data")
        span.set_attribute("http.method", "GET")
        
        # Simulate data processing
        with tracer.start_as_current_span("data.process") as process_span:
            time.sleep(random.uniform(0.05, 0.15))
            data = {
                "timestamp": time.time(),
                "value": random.randint(1, 100),
                "status": "success",
                "environment": os.getenv("ENVIRONMENT", "unknown")
            }
            process_span.set_attribute("output.fields", len(data))
        
        span.set_attribute("response.status", "success")
        logger.info(f"Generated data: {data}")
        request_counter.labels(endpoint="/api/data", method="GET").inc()
        duration = time.time() - start_time
        request_duration.labels(endpoint="/api/data").observe(duration)
        
        return jsonify(data)

@app.route('/api/slow')
def slow_endpoint():
    start_time = time.time()
    with tracer.start_as_current_span("slow_endpoint") as span:
        span.set_attribute("http.route", "/api/slow")
        span.set_attribute("http.method", "GET")
        
        logger.warning("Slow endpoint called - complex operation starting")
        
        # Simulate slow operation
        with tracer.start_as_current_span("compute.heavy_calculation") as compute_span:
            compute_span.set_attribute("compute.type", "matrix_multiplication")
            delay = random.uniform(0.5, 1.5)
            time.sleep(delay)
            compute_span.set_attribute("compute.duration_ms", int(delay * 1000))
        
        total_duration = time.time() - start_time
        span.set_attribute("total.duration_seconds", round(total_duration, 2))
        logger.warning(f"Slow operation completed in {total_duration:.2f}s")
        
        request_counter.labels(endpoint="/api/slow", method="GET").inc()
        request_duration.labels(endpoint="/api/slow").observe(total_duration)
        
        return jsonify({
            "message": "Slow operation completed",
            "duration_seconds": round(total_duration, 2)
        })

@app.route('/api/error')
def error_endpoint():
    with tracer.start_as_current_span("error_endpoint") as span:
        span.set_attribute("http.route", "/api/error")
        span.set_attribute("http.method", "GET")
        
        # Randomly generate different types of errors
        error_type = random.choice(["db_error", "timeout", "validation_error", "not_found"])
        
        span.set_attribute("error", True)
        span.set_attribute("error.type", error_type)
        error_counter.labels(type=error_type, endpoint="/api/error").inc()
        
        if error_type == "db_error":
            logger.error("Database error occurred")
            return jsonify({"error": "Database error"}), 500
        elif error_type == "timeout":
            logger.error("Request timeout")
            return jsonify({"error": "Request timeout"}), 408
        elif error_type == "validation_error":
            logger.error("Validation error")
            return jsonify({"error": "Validation failed"}), 400
        else:
            logger.error("Resource not found")
            return jsonify({"error": "Resource not found"}), 404

@app.route('/health')
def health():
    return jsonify({"status": "healthy", "environment": os.getenv("ENVIRONMENT", "unknown")})

@app.route('/ready')
def ready():
    return jsonify({"status": "ready"})

if __name__ == '__main__':
    logger.info(f"Starting instrumented application on port 8080")
    logger.info(f"Environment: {os.getenv('ENVIRONMENT', 'unknown')}")
    logger.info(f"Service: {os.getenv('OTEL_SERVICE_NAME', 'instrumented-app')}")
    logger.info(f"OTLP Traces Endpoint: {traces_endpoint}")
    logger.info(f"Prometheus Metrics: http://0.0.0.0:8080/metrics")
    app.run(host='0.0.0.0', port=8080, debug=False)

