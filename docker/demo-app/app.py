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
    "service.name": os.getenv("OTEL_SERVICE_NAME", "demo-app"),
    "service.version": "1.0.0",
    "deployment.environment": "docker-compose"
})

# Setup Logging
logger_provider = LoggerProvider(resource=resource)
set_logger_provider(logger_provider)
log_exporter = OTLPLogExporter(
    endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317"),
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
    endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317"),
    insecure=True
)
span_processor = BatchSpanProcessor(otlp_exporter)
tracer_provider.add_span_processor(span_processor)

# Setup Metrics
metric_reader = PeriodicExportingMetricReader(
    OTLPMetricExporter(
        endpoint=os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317"),
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
    "demo_requests_total",
    description="Total number of requests",
    unit="1"
)

request_duration = meter.create_histogram(
    "demo_request_duration_seconds",
    description="Request duration in seconds",
    unit="s"
)

error_counter = meter.create_counter(
    "demo_errors_total",
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
            "message": "LGTM+O Stack Demo Application",
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
        
        # Step 1: Check cache first
        with tracer.start_as_current_span("cache.check") as cache_span:
            cache_span.set_attribute("cache.type", "redis")
            cache_span.set_attribute("cache.key", "users:list")
            time.sleep(random.uniform(0.005, 0.015))
            cache_hit = random.choice([True, False])
            cache_span.set_attribute("cache.hit", cache_hit)
            
            if cache_hit:
                logger.info("Cache hit for users list")
            else:
                logger.info("Cache miss for users list")
        
        if not cache_hit:
            # Step 2: Query database
            with tracer.start_as_current_span("db.query") as db_span:
                db_span.set_attribute("db.system", "postgresql")
                db_span.set_attribute("db.name", "userdb")
                db_span.set_attribute("db.statement", "SELECT * FROM users WHERE active = true")
                db_span.set_attribute("db.operation", "SELECT")
                
                # Simulate connection pool wait
                with tracer.start_as_current_span("db.connection.acquire"):
                    time.sleep(random.uniform(0.002, 0.008))
                
                # Simulate query execution
                with tracer.start_as_current_span("db.query.execute"):
                    time.sleep(random.uniform(0.02, 0.08))
                
                users = [
                    {"id": 1, "name": "Alice", "email": "alice@example.com"},
                    {"id": 2, "name": "Bob", "email": "bob@example.com"},
                    {"id": 3, "name": "Charlie", "email": "charlie@example.com"}
                ]
                
                db_span.set_attribute("db.rows_returned", len(users))
                logger.info(f"Retrieved {len(users)} users from database")
            
            # Step 3: Enrich with additional data
            with tracer.start_as_current_span("service.enrich_users") as enrich_span:
                enrich_span.set_attribute("enrichment.type", "profile_data")
                
                for user in users:
                    # Simulate external API call for each user
                    with tracer.start_as_current_span("http.get_user_profile") as api_span:
                        api_span.set_attribute("http.url", f"https://api.profiles.com/v1/users/{user['id']}")
                        api_span.set_attribute("http.method", "GET")
                        api_span.set_attribute("user.id", user['id'])
                        time.sleep(random.uniform(0.01, 0.03))
                
                enrich_span.set_attribute("users.enriched", len(users))
            
            # Step 4: Update cache
            with tracer.start_as_current_span("cache.set") as cache_set_span:
                cache_set_span.set_attribute("cache.type", "redis")
                cache_set_span.set_attribute("cache.key", "users:list")
                cache_set_span.set_attribute("cache.ttl", 300)
                time.sleep(random.uniform(0.005, 0.015))
                logger.info("Updated cache with users list")
        else:
            users = [
                {"id": 1, "name": "Alice", "email": "alice@example.com"},
                {"id": 2, "name": "Bob", "email": "bob@example.com"},
                {"id": 3, "name": "Charlie", "email": "charlie@example.com"}
            ]
        
        span.set_attribute("user.count", len(users))
        span.set_attribute("response.size_bytes", len(str(users)))
        
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
        
        # Step 1: Authenticate request
        with tracer.start_as_current_span("auth.validate_token") as auth_span:
            auth_span.set_attribute("auth.method", "jwt")
            time.sleep(random.uniform(0.005, 0.015))
            auth_span.set_attribute("auth.user_id", "user_" + str(random.randint(100, 999)))
            logger.info("Token validated successfully")
        
        # Step 2: Fetch from multiple data sources
        with tracer.start_as_current_span("data.aggregate") as agg_span:
            
            # Query time-series database
            with tracer.start_as_current_span("timeseries.query") as ts_span:
                ts_span.set_attribute("db.system", "influxdb")
                ts_span.set_attribute("db.query", "SELECT mean(value) FROM metrics WHERE time > now() - 1h")
                time.sleep(random.uniform(0.02, 0.05))
                ts_value = random.randint(1, 100)
                ts_span.set_attribute("query.result_count", 1)
            
            # Query analytics database
            with tracer.start_as_current_span("analytics.query") as analytics_span:
                analytics_span.set_attribute("db.system", "clickhouse")
                analytics_span.set_attribute("db.query", "SELECT count(*) FROM events WHERE date = today()")
                time.sleep(random.uniform(0.03, 0.07))
                analytics_span.set_attribute("query.result_count", random.randint(1000, 5000))
            
            # Call ML prediction service
            with tracer.start_as_current_span("ml.predict") as ml_span:
                ml_span.set_attribute("ml.model", "forecast-v2")
                ml_span.set_attribute("ml.input_features", 5)
                
                with tracer.start_as_current_span("ml.preprocessing"):
                    time.sleep(random.uniform(0.01, 0.02))
                
                with tracer.start_as_current_span("ml.inference"):
                    time.sleep(random.uniform(0.02, 0.04))
                    ml_span.set_attribute("ml.confidence", round(random.uniform(0.8, 0.99), 2))
            
            agg_span.set_attribute("sources.count", 3)
        
        # Step 3: Process and transform data
        with tracer.start_as_current_span("data.transform") as transform_span:
            transform_span.set_attribute("transform.operations", "normalize,aggregate,filter")
            time.sleep(random.uniform(0.01, 0.03))
            
            data = {
                "timestamp": time.time(),
                "value": ts_value,
                "status": "success",
                "confidence": round(random.uniform(0.8, 0.99), 2)
            }
            transform_span.set_attribute("output.fields", len(data))
        
        # Step 4: Store result in cache for future requests
        with tracer.start_as_current_span("cache.store") as cache_span:
            cache_span.set_attribute("cache.type", "redis")
            cache_span.set_attribute("cache.key", f"data:{int(time.time())}")
            cache_span.set_attribute("cache.ttl", 60)
            time.sleep(random.uniform(0.005, 0.010))
        
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
        
        # Step 1: Heavy computation
        with tracer.start_as_current_span("compute.heavy_calculation") as compute_span:
            compute_span.set_attribute("compute.type", "matrix_multiplication")
            compute_span.set_attribute("compute.size", 1000)
            delay1 = random.uniform(0.2, 0.5)
            time.sleep(delay1)
            compute_span.set_attribute("compute.duration_ms", int(delay1 * 1000))
        
        # Step 2: Multiple slow database queries
        with tracer.start_as_current_span("db.batch_queries") as batch_span:
            batch_span.set_attribute("db.query_count", 3)
            
            with tracer.start_as_current_span("db.query_aggregation") as q1:
                q1.set_attribute("db.statement", "SELECT * FROM orders JOIN customers")
                time.sleep(random.uniform(0.15, 0.3))
            
            with tracer.start_as_current_span("db.query_analytics") as q2:
                q2.set_attribute("db.statement", "SELECT date, SUM(amount) FROM transactions GROUP BY date")
                time.sleep(random.uniform(0.1, 0.25))
            
            with tracer.start_as_current_span("db.query_reports") as q3:
                q3.set_attribute("db.statement", "SELECT * FROM reports WHERE status = 'pending'")
                time.sleep(random.uniform(0.1, 0.2))
        
        # Step 3: External API calls (sequential - intentionally slow)
        with tracer.start_as_current_span("external.api_calls") as api_span:
            api_span.set_attribute("api.call_count", 3)
            
            with tracer.start_as_current_span("http.post_notification") as notif:
                notif.set_attribute("http.url", "https://notifications.service/api/send")
                notif.set_attribute("http.method", "POST")
                time.sleep(random.uniform(0.15, 0.3))
            
            with tracer.start_as_current_span("http.get_weather") as weather:
                weather.set_attribute("http.url", "https://weather.api/current")
                weather.set_attribute("http.method", "GET")
                time.sleep(random.uniform(0.1, 0.25))
            
            with tracer.start_as_current_span("http.update_inventory") as inventory:
                inventory.set_attribute("http.url", "https://inventory.service/api/sync")
                inventory.set_attribute("http.method", "PUT")
                time.sleep(random.uniform(0.1, 0.2))
        
        total_duration = time.time() - start_time
        span.set_attribute("total.duration_seconds", round(total_duration, 2))
        logger.warning(f"Slow operation completed in {total_duration:.2f}s")
        
        request_counter.add(1, {"endpoint": "/api/slow", "method": "GET"})
        request_duration.record(total_duration, {"endpoint": "/api/slow"})
        
        return jsonify({
            "message": "Slow operation completed",
            "duration_seconds": round(total_duration, 2),
            "operations": ["compute", "database_queries", "external_apis"]
        })

@app.route('/api/error')
def error_endpoint():
    with tracer.start_as_current_span("error_endpoint") as span:
        span.set_attribute("http.route", "/api/error")
        span.set_attribute("http.method", "GET")
        
        # Start processing - simulate everything going fine at first
        with tracer.start_as_current_span("auth.check") as auth_span:
            auth_span.set_attribute("auth.method", "bearer")
            time.sleep(random.uniform(0.01, 0.02))
            auth_span.set_attribute("auth.success", True)
        
        # Randomly generate different types of errors at different stages
        error_type = random.choice(["db_error", "api_timeout", "validation_error", "not_found"])
        
        if error_type == "db_error":
            with tracer.start_as_current_span("db.transaction") as db_span:
                db_span.set_attribute("db.system", "postgresql")
                db_span.set_attribute("db.operation", "UPDATE")
                
                with tracer.start_as_current_span("db.begin_transaction"):
                    time.sleep(random.uniform(0.005, 0.01))
                
                with tracer.start_as_current_span("db.execute_query") as query_span:
                    time.sleep(random.uniform(0.02, 0.04))
                    # Error happens here
                    query_span.set_attribute("error", True)
                    query_span.set_attribute("error.type", "deadlock")
                    query_span.set_attribute("error.message", "Deadlock detected")
                    logger.error("Database deadlock error occurred")
                
                db_span.set_attribute("error", True)
                db_span.set_attribute("error.type", "database_error")
                
            span.set_attribute("error", True)
            span.set_attribute("error.type", "db_error")
            error_counter.add(1, {"type": "db_error", "endpoint": "/api/error"})
            return jsonify({"error": "Database error - transaction deadlock"}), 500
            
        elif error_type == "api_timeout":
            with tracer.start_as_current_span("business.process_order") as process_span:
                with tracer.start_as_current_span("cache.get"):
                    time.sleep(random.uniform(0.005, 0.01))
                
                with tracer.start_as_current_span("http.call_payment_api") as payment_span:
                    payment_span.set_attribute("http.url", "https://payment.gateway/api/charge")
                    payment_span.set_attribute("http.method", "POST")
                    time.sleep(random.uniform(0.5, 1.0))  # Simulate timeout
                    payment_span.set_attribute("error", True)
                    payment_span.set_attribute("error.type", "timeout")
                    payment_span.set_attribute("error.message", "Request timeout after 30s")
                    logger.error("Payment API timeout")
                
                process_span.set_attribute("error", True)
                process_span.set_attribute("error.type", "downstream_timeout")
            
            span.set_attribute("error", True)
            span.set_attribute("error.type", "api_timeout")
            error_counter.add(1, {"type": "timeout", "endpoint": "/api/error"})
            return jsonify({"error": "Payment service timeout"}), 408
            
        elif error_type == "validation_error":
            with tracer.start_as_current_span("validation.check_input") as val_span:
                with tracer.start_as_current_span("validation.schema_check"):
                    time.sleep(random.uniform(0.005, 0.01))
                
                with tracer.start_as_current_span("validation.business_rules") as rules_span:
                    time.sleep(random.uniform(0.01, 0.02))
                    rules_span.set_attribute("error", True)
                    rules_span.set_attribute("error.type", "validation_failed")
                    rules_span.set_attribute("error.message", "Invalid email format")
                    logger.error("Validation error: Invalid email format")
                
                val_span.set_attribute("error", True)
                val_span.set_attribute("validation.failed_field", "email")
            
            span.set_attribute("error", True)
            span.set_attribute("error.type", "validation_error")
            error_counter.add(1, {"type": "validation", "endpoint": "/api/error"})
            return jsonify({"error": "Validation failed", "field": "email"}), 400
            
        else:  # not_found
            with tracer.start_as_current_span("db.find_resource") as find_span:
                find_span.set_attribute("db.system", "postgresql")
                find_span.set_attribute("db.statement", "SELECT * FROM resources WHERE id = $1")
                time.sleep(random.uniform(0.02, 0.04))
                find_span.set_attribute("db.rows_returned", 0)
                find_span.set_attribute("error", True)
                find_span.set_attribute("error.type", "not_found")
                logger.error("Resource not found in database")
            
            span.set_attribute("error", True)
            span.set_attribute("error.type", "not_found")
            error_counter.add(1, {"type": "not_found", "endpoint": "/api/error"})
            return jsonify({"error": "Resource not found"}), 404

@app.route('/health')
def health():
    return jsonify({"status": "healthy"})

# Background task to generate periodic telemetry
def generate_background_activity():
    import threading
    
    def background_job():
        while True:
            with tracer.start_as_current_span("background_job") as span:
                logger.info("Background job running")
                span.set_attribute("job.type", "periodic")
                
                # Simulate some work
                time.sleep(random.uniform(1, 3))
                
                # Generate random metric
                value = random.randint(0, 100)
                span.set_attribute("job.result", value)
            
            time.sleep(10)
    
    thread = threading.Thread(target=background_job, daemon=True)
    thread.start()

if __name__ == '__main__':
    generate_background_activity()
    logger.info("Starting demo application on port 8080")
    app.run(host='0.0.0.0', port=8080, debug=False)

