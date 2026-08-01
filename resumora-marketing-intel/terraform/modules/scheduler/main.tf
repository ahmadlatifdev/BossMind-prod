variable "project_id" { type = string }
variable "region" { type = string }
variable "timezone" { type = string }
variable "cloud_run_base_url" { type = string }
variable "service_account_email" { type = string }
variable "enable_scheduler" { type = bool }

locals {
  # Scheduler only when we have a real HTTPS Cloud Run URL
  active = var.enable_scheduler && startswith(var.cloud_run_base_url, "https://")
  base   = trimsuffix(var.cloud_run_base_url, "/")
}

# Daily brand perception (Gemini Flash-Lite via Cloud Run job route)
resource "google_cloud_scheduler_job" "brand_analysis" {
  count = local.active ? 1 : 0

  name             = "resumora-mkt-brand-analysis-daily"
  description      = "Daily brand perception analysis (Flash-Lite). Does NOT touch ads."
  schedule         = "0 6 * * *"
  time_zone        = var.timezone
  project          = var.project_id
  region           = var.region
  attempt_deadline = "320s"

  http_target {
    http_method = "POST"
    uri         = "${local.base}/api/brand-analysis"

    oidc_token {
      service_account_email = var.service_account_email
      audience              = local.base
    }
  }

  retry_config {
    retry_count          = 3
    max_retry_duration   = "600s"
    min_backoff_duration = "60s"
    max_backoff_duration = "300s"
  }
}

# Weekly competitor pricing scrape
resource "google_cloud_scheduler_job" "competitor_scrape" {
  count = local.active ? 1 : 0

  name             = "resumora-mkt-competitor-scrape-weekly"
  description      = "Weekly competitor price scrape — advisory only"
  schedule         = "0 8 * * 1"
  time_zone        = var.timezone
  project          = var.project_id
  region           = var.region
  attempt_deadline = "600s"

  http_target {
    http_method = "POST"
    uri         = "${local.base}/api/competitor-scrape"

    oidc_token {
      service_account_email = var.service_account_email
      audience              = local.base
    }
  }

  retry_config {
    retry_count        = 3
    max_retry_duration = "600s"
  }
}

# Monthly pricing model retrain (batch — cheapest cadence)
resource "google_cloud_scheduler_job" "pricing_model_retrain" {
  count = local.active ? 1 : 0

  name             = "resumora-mkt-pricing-retrain-monthly"
  description      = "Monthly batch pricing model retrain (no online Vertex endpoint)"
  schedule         = "0 10 1 * *"
  time_zone        = var.timezone
  project          = var.project_id
  region           = var.region
  attempt_deadline = "1800s"

  http_target {
    http_method = "POST"
    uri         = "${local.base}/api/model-retrain"

    oidc_token {
      service_account_email = var.service_account_email
      audience              = local.base
    }
  }

  retry_config {
    retry_count        = 2
    max_retry_duration = "1800s"
  }
}
