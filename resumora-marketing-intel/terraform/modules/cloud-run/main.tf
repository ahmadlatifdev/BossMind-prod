variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "service_name" { type = string }
variable "image" { type = string }
variable "dataset_name" { type = string }
variable "service_account_email" { type = string }
variable "enable_public_access" { type = bool }
variable "labels" { type = map(string) }

locals {
  create = var.image != ""
}

resource "google_cloud_run_v2_service" "dashboard" {
  count = local.create ? 1 : 0

  name     = var.service_name
  location = var.region
  project  = var.project_id
  ingress  = "INGRESS_TRAFFIC_ALL"

  labels = merge(var.labels, {
    service = "dashboard"
  })

  template {
    service_account = var.service_account_email

    scaling {
      min_instance_count = 0 # COST: scale to zero → $0 when idle
      max_instance_count = 3
    }

    containers {
      image = var.image

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "2Gi"
        }
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "BIGQUERY_PROJECT"
        value = var.project_id
      }
      env {
        name  = "BIGQUERY_DATASET"
        value = var.dataset_name
      }
      env {
        name  = "BQ_DATASET"
        value = var.dataset_name
      }
      env {
        name  = "ENVIRONMENT"
        value = var.environment
      }
      # Safety locks — never enable ad writes from infra
      env {
        name  = "AD_PLATFORM_WRITE_ENABLED"
        value = "false"
      }
      env {
        name  = "AUTO_APPLY_PRICE_CHANGES"
        value = "false"
      }
      env {
        name  = "GEMINI_MODEL"
        value = "gemini-2.0-flash-lite"
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
}

resource "google_cloud_run_v2_service_iam_member" "public_access" {
  count = local.create && var.enable_public_access ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.dashboard[0].name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "service_uri" {
  value = local.create ? google_cloud_run_v2_service.dashboard[0].uri : ""
}

output "service_ready" {
  value = local.create
}

output "brand_job_path" {
  value = "/api/brand-analysis"
}

output "train_job_path" {
  value = "/api/model-retrain"
}
