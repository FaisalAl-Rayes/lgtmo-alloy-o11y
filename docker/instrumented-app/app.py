import os
import time
import random
import logging
from flask import Flask, jsonify, request
from opentelemetry import trace, metrics
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
from opentelemetry.sdk._logs.export import BatchLogRecordProcessor
from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter
from opentelemetry._logs import set_logger_provider

# Configure OpenTelemetry Resource (shared across all signals)
resource = Resource.create({
    "service.name": os.getenv("OTEL_SERVICE_NAME", "instrumented-app"),
    "service.version": "1.0.0",
    "deployment.environment": os.getenv("ENVIRONMENT", "unknown"),
    "service.namespace": os.getenv("NAMESPACE", "default")
})

# Get Alloy endpoint from environment
alloy_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://alloy.default.svc.cluster.local:4317")

# Setup Logging
logger_provider = LoggerProvider(resource=resource)
set_logger_provider(logger_provider)
log_exporter = OTLPLogExporter(
    endpoint=alloy_endpoint,
    insecure=True
)
logger_provider.add_log_record_processor(BatchLogRecordProcessor(log_exporter))

# Configure Python logging to use OpenTelemetry
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)
handler = LoggingHandler(logger_provider=logger_provider)
logger.addHandler(handler)

# Setup Tracing
trace.set_tracer_provider(TracerProvider(resource=resource))
tracer_provider = trace.get_tracer_provider()
otlp_exporter = OTLPSpanExporter(
    endpoint=alloy_endpoint,
    insecure=True
)
span_processor = BatchSpanProcessor(otlp_exporter)
tracer_provider.add_span_processor(span_processor)

# Setup Metrics
metric_reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(
        endpoint=alloy_endpoint,
        insecure=True
    ),
    export_interval_millis=5000
)
metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[metric_reader]))

# Create Flask app
app = Flask(__name__)

# Instrument Flask with OpenTelemetry
FlaskInstrumentor().instrument_app(app)

# Get tracer and meter
tracer = trace.get_tracer(__name__)
meter = metrics.get_meter(__name__)

# Create custom metrics
request_counter = meter.create_counter(
    "app_requests_total",
    description="Total number of requests",
    unit="1"
)

request_duration = meter.create_histogram(
    "app_request_duration_seconds",
    description="Request duration in seconds",
    unit="s"
)

error_counter = meter.create_counter(
    "app_errors_total",
    description="Total number of errors",
    unit="1"
)

@app.route('/')
def home():
    with tracer.start_as_current_span("home") as span:
        span.set_attribute("http.route", "/")
        logger.info("Home endpoint accessed")
        request_counter.add(1, {"endpoint": "/", "method": "GET"})
        
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
                "/health"
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
        request_counter.add(1, {"endpoint": "/api/users", "method": "GET"})
        duration = time.time() - start_time
        request_duration.record(duration, {"endpoint": "/api/users"})
        
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
        request_counter.add(1, {"endpoint": "/api/data", "method": "GET"})
        duration = time.time() - start_time
        request_duration.record(duration, {"endpoint": "/api/data"})
        
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
        
        request_counter.add(1, {"endpoint": "/api/slow", "method": "GET"})
        request_duration.record(total_duration, {"endpoint": "/api/slow"})
        
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
        error_counter.add(1, {"type": error_type, "endpoint": "/api/error"})
        
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
    logger.info(f"OTLP Endpoint: {alloy_endpoint}")
    app.run(host='0.0.0.0', port=8080, debug=False)

