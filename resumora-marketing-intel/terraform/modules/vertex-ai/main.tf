# Vertex AI — batch-oriented endpoint only (no always-on dedicated prediction nodes).
# Pricing/segmentation: Cloud Run / local sklearn batch jobs.
# Brand: Gemini Flash-Lite via /api/brand-analysis.
# Idle Vertex endpoint with no deployed models ≈ $0 compute.

variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "dataset_name" { type = string }
variable "bucket_name" { type = string }
variable "labels" { type = map(string) }

resource "google_vertex_ai_endpoint" "batch_endpoint" {
  name         = "resumora-mkt-batch-endpoint-${var.environment}"
  display_name = "Resumora Marketing Batch Endpoint"
  description  = "Optional Vertex endpoint for future batch predictions. Do not attach always-on replicas."
  location     = var.region
  project      = var.project_id

  labels = merge(var.labels, {
    usage_type = "batch-only"
  })
}

# Batch prediction jobs are created at runtime by Cloud Scheduler → Cloud Run
# (/api/model-retrain), not as always-on Terraform-managed Vertex machines.
# Keeping jobs out of Terraform avoids accidental dedicated replica costs.

output "endpoint_name" {
  value = google_vertex_ai_endpoint.batch_endpoint.name
}

output "endpoint_id" {
  value = google_vertex_ai_endpoint.batch_endpoint.id
}

output "batch_note" {
  value = "Trigger batch via Cloud Run /api/model-retrain — input BQ ${var.dataset_name}.user_behavior → gs://${var.bucket_name}/predictions/"
}
