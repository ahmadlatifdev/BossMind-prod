variable "project_id" {
  description = "GCP Project ID (Resumora production: resumora-live)"
  type        = string
  default     = "resumora-live"
}

variable "billing_account_id" {
  description = "GCP Billing Account ID (required when enable_budget_alert=true)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_budget_alert" {
  description = "Create billing budget at 90%/100% thresholds"
  type        = bool
  default     = false
}

variable "region" {
  description = "GCP Region (us-central1 qualifies for free tier)"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

variable "environment" {
  description = "Environment name (dev/staging/prod)"
  type        = string
  default     = "dev"
}

variable "budget_amount_usd" {
  description = "Monthly budget alert threshold in USD"
  type        = number
  default     = 50
}

variable "bigquery_dataset_name" {
  description = "BigQuery dataset name (must match Python BQ_DATASET)"
  type        = string
  default     = "resumora_mkt_intel"
}

variable "bigquery_table_expiration_days" {
  description = "Days before partitioned table data expires (cost control)"
  type        = number
  default     = 90
}

variable "cloud_run_service_name" {
  description = "Cloud Run service name"
  type        = string
  default     = "resumora-mkt-intel-dash"
}

variable "cloud_run_image" {
  description = "Container image URL for Cloud Run (empty = skip service create)"
  type        = string
  default     = ""
}

variable "enable_public_dashboard" {
  description = "If true, grant roles/run.invoker to allUsers (prefer false + IAP/team emails)"
  type        = bool
  default     = false
}

variable "enable_scheduler" {
  description = "Create Cloud Scheduler jobs (requires a live Cloud Run URL)"
  type        = bool
  default     = true
}

variable "scheduler_timezone" {
  description = "Timezone for Cloud Scheduler"
  type        = string
  default     = "America/Toronto"
}

variable "storage_bucket_name" {
  description = "Optional explicit GCS bucket name"
  type        = string
  default     = null
}
