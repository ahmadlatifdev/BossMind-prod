import sentry_sdk
from sentry_sdk import capture_exception, capture_message

# Initialize Sentry (replace YOUR_DSN with your actual Sentry DSN from sentry.io)
sentry_sdk.init(
    dsn="YOUR_SENTRY_DSN_HERE",
    traces_sample_rate=1.0,  # Capture 100% of transactions for now
    environment="development",
    release="miki-v1.0"
)

def log_to_sentry(message, level="info"):
    """Send logs to Sentry"""
    if level == "error":
        capture_message(message, level="error")
    else:
        capture_message(message, level="info")

def capture_agent_error(agent_name, task_type, error):
    """Capture agent errors with context"""
    with sentry_sdk.push_scope() as scope:
        scope.set_tag("agent", agent_name)
        scope.set_tag("task_type", task_type)
        capture_exception(error)

print("✅ Sentry integration ready")
