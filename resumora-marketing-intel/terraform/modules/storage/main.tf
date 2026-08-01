variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "bucket_name" { type = string }
variable "labels" { type = map(string) }

resource "google_storage_bucket" "marketing_data" {
  name                        = var.bucket_name
  project                     = var.project_id
  location                    = var.region
  force_destroy               = false
  uniform_bucket_level_access = true

  versioning {
    enabled = false # COST: disable versioning
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 365
    }
    action {
      type = "Delete"
    }
  }

  labels = merge(var.labels, {
    storage_tier = "auto-lifecycle"
  })
}

resource "google_service_account" "marketing_sa" {
  account_id   = "resumora-mkt-intel"
  project      = var.project_id
  display_name = "Resumora Marketing Intelligence SA"
  description  = "Least-privilege SA for marketing AI — no Ads Admin roles"
}

# Least privilege — analytics + AI + logging. No ads.campaigns mutate roles.
resource "google_project_iam_member" "bigquery_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.marketing_sa.email}"
}

resource "google_project_iam_member" "bigquery_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.marketing_sa.email}"
}

resource "google_project_iam_member" "storage_object_admin" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.marketing_sa.email}"
}

resource "google_project_iam_member" "aiplatform_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.marketing_sa.email}"
}

resource "google_project_iam_member" "logging_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.marketing_sa.email}"
}

resource "google_project_iam_member" "run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.marketing_sa.email}"
}

output "bucket_name" {
  value = google_storage_bucket.marketing_data.name
}

output "service_account_email" {
  value = google_service_account.marketing_sa.email
}
