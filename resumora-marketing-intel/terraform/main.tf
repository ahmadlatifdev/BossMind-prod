# Resumora Marketing Intelligence — Terraform root
# Enforces: scale-to-zero Cloud Run, batch-oriented Vertex, BQ partition/cluster,
# GCS lifecycle, budget alerts. Never grants Ads Admin roles.

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }

  # Remote state — CI enables via backend.tf; local may use -backend=false
  # bucket = "resumora-terraform-state-resumora-live"
  # prefix = "marketing-intelligence"
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  labels = {
    environment = var.environment
    cost_center = "marketing-ai"
    project     = "resumora"
    ads         = "no-write"
  }
}

# ------------------------------------------------------------
# COST: Budget alerts at 90% / 100%
# Requires billing.budgets permission on the billing account.
# Set enable_budget_alert=false if you lack billing admin rights.
# ------------------------------------------------------------
resource "google_billing_budget" "marketing_budget" {
  count = var.enable_budget_alert ? 1 : 0

  billing_account = var.billing_account_id
  display_name    = "Resumora Marketing Intelligence Budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.budget_amount_usd)
    }
  }

  threshold_rules {
    threshold_percent = 0.9
  }

  threshold_rules {
    threshold_percent = 1.0
  }
}

module "storage" {
  source       = "./modules/storage"
  project_id   = var.project_id
  region       = var.region
  environment  = var.environment
  bucket_name  = coalesce(var.storage_bucket_name, "${var.project_id}-mkt-intel-data")
  labels       = local.labels
}

module "bigquery" {
  source                = "./modules/bigquery"
  project_id            = var.project_id
  region                = var.region
  environment           = var.environment
  dataset_name          = var.bigquery_dataset_name
  table_expiration_days = var.bigquery_table_expiration_days
  labels                = local.labels
}

module "vertex_ai" {
  source       = "./modules/vertex-ai"
  project_id   = var.project_id
  region       = var.region
  environment  = var.environment
  dataset_name = var.bigquery_dataset_name
  bucket_name  = module.storage.bucket_name
  labels       = local.labels
}

module "cloud_run" {
  source                = "./modules/cloud-run"
  project_id            = var.project_id
  region                = var.region
  environment           = var.environment
  service_name          = var.cloud_run_service_name
  image                 = var.cloud_run_image
  dataset_name          = var.bigquery_dataset_name
  service_account_email = module.storage.service_account_email
  enable_public_access  = var.enable_public_dashboard
  labels                = local.labels
}

module "scheduler" {
  source                = "./modules/scheduler"
  project_id            = var.project_id
  region                = var.region
  timezone              = var.scheduler_timezone
  cloud_run_base_url    = module.cloud_run.service_uri
  service_account_email = module.storage.service_account_email
  enable_scheduler      = var.enable_scheduler && module.cloud_run.service_ready
}
