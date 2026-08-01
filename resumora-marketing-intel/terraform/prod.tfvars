# Production variable values for CI / local apply (non-secret SA keys).
project_id         = "resumora-live"
region             = "us-central1"
zone               = "us-central1-a"
environment        = "prod"
budget_amount_usd  = 50
enable_budget_alert = false

# Linked billing account for resumora-live (budget alerts remain OFF until enabled)
billing_account_id = "015A54-74DD88-E8FFC4"

bigquery_dataset_name          = "resumora_mkt_intel"
bigquery_table_expiration_days = 90

cloud_run_service_name = "resumora-mkt-intel-dash"
# Empty until first container build — Cloud Run + Scheduler stay skipped safely
cloud_run_image         = ""
enable_public_dashboard = false
enable_scheduler        = true
scheduler_timezone      = "America/Toronto"
