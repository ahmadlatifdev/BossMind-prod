output "bigquery_dataset_id" {
  value       = module.bigquery.dataset_id
  description = "BigQuery dataset ID"
}

output "cloud_run_url" {
  value       = module.cloud_run.service_uri
  description = "Cloud Run service URL (empty if image not set)"
}

output "vertex_ai_endpoint_name" {
  value       = module.vertex_ai.endpoint_name
  description = "Vertex AI endpoint name (batch-oriented; idle cost ~$0)"
}

output "storage_bucket_name" {
  value       = module.storage.bucket_name
  description = "Cloud Storage bucket name"
}

output "service_account_email" {
  value       = module.storage.service_account_email
  description = "Least-privilege runtime service account"
  sensitive   = true
}

output "safety_note" {
  value       = "AD platform writes are NOT granted by this Terraform. Pricing changes remain human-approved."
  description = "Operational safety reminder"
}
