variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "dataset_name" { type = string }
variable "table_expiration_days" { type = number }
variable "labels" { type = map(string) }

locals {
  expiration_ms = var.table_expiration_days * 86400000
}

resource "google_bigquery_dataset" "marketing" {
  dataset_id                  = var.dataset_name
  project                     = var.project_id
  friendly_name               = "Resumora Marketing Intelligence"
  description                 = "Central warehouse for pricing/brand analysis — no ad platform writes"
  location                    = "US"
  default_table_expiration_ms = local.expiration_ms
  labels                      = var.labels
  delete_contents_on_destroy  = false
}

# User behavioral data — partitioned + clustered (query cost control)
resource "google_bigquery_table" "user_behavior" {
  dataset_id = google_bigquery_dataset.marketing.dataset_id
  project    = var.project_id
  table_id   = "user_behavior"

  time_partitioning {
    type          = "DAY"
    field         = "event_date"
    expiration_ms = local.expiration_ms
  }

  clustering = ["user_segment", "event_type"]

  schema = <<EOF
[
  {"name": "user_id", "type": "STRING", "mode": "REQUIRED"},
  {"name": "event_date", "type": "DATE", "mode": "REQUIRED"},
  {"name": "event_type", "type": "STRING", "mode": "REQUIRED"},
  {"name": "user_segment", "type": "STRING", "mode": "NULLABLE"},
  {"name": "price_paid", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "conversion_flag", "type": "BOOLEAN", "mode": "NULLABLE"}
]
EOF
}

resource "google_bigquery_table" "competitor_pricing" {
  dataset_id = google_bigquery_dataset.marketing.dataset_id
  project    = var.project_id
  table_id   = "competitor_pricing"

  time_partitioning {
    type          = "DAY"
    field         = "scrape_date"
    expiration_ms = local.expiration_ms
  }

  clustering = ["competitor_name"]

  schema = <<EOF
[
  {"name": "competitor_name", "type": "STRING", "mode": "REQUIRED"},
  {"name": "scrape_date", "type": "DATE", "mode": "REQUIRED"},
  {"name": "price", "type": "FLOAT", "mode": "REQUIRED"},
  {"name": "product_tier", "type": "STRING", "mode": "NULLABLE"},
  {"name": "prev_price", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "url", "type": "STRING", "mode": "NULLABLE"}
]
EOF
}

resource "google_bigquery_table" "brand_analysis" {
  dataset_id = google_bigquery_dataset.marketing.dataset_id
  project    = var.project_id
  table_id   = "brand_analysis"

  time_partitioning {
    type          = "DAY"
    field         = "analysis_date"
    expiration_ms = local.expiration_ms
  }

  schema = <<EOF
[
  {"name": "analysis_date", "type": "DATE", "mode": "REQUIRED"},
  {"name": "brand_name", "type": "STRING", "mode": "REQUIRED"},
  {"name": "sentiment_score", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "key_themes", "type": "STRING", "mode": "REPEATED"},
  {"name": "raw_analysis", "type": "STRING", "mode": "NULLABLE"}
]
EOF
}

# Extra tables used by the Python MVP package
resource "google_bigquery_table" "pricing_history" {
  dataset_id = google_bigquery_dataset.marketing.dataset_id
  project    = var.project_id
  table_id   = "pricing_history"

  schema = <<EOF
[
  {"name": "observed_at", "type": "TIMESTAMP", "mode": "NULLABLE"},
  {"name": "plan_id", "type": "STRING", "mode": "NULLABLE"},
  {"name": "plan_name", "type": "STRING", "mode": "NULLABLE"},
  {"name": "price_usd", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "currency", "type": "STRING", "mode": "NULLABLE"},
  {"name": "source", "type": "STRING", "mode": "NULLABLE"}
]
EOF
}

resource "google_bigquery_table" "model_recommendations" {
  dataset_id = google_bigquery_dataset.marketing.dataset_id
  project    = var.project_id
  table_id   = "model_recommendations"

  time_partitioning {
    type = "DAY"
  }

  schema = <<EOF
[
  {"name": "generated_at", "type": "TIMESTAMP", "mode": "NULLABLE"},
  {"name": "segment_id", "type": "INTEGER", "mode": "NULLABLE"},
  {"name": "segment_label", "type": "STRING", "mode": "NULLABLE"},
  {"name": "current_price", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "recommended_price", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "confidence", "type": "FLOAT", "mode": "NULLABLE"},
  {"name": "rationale", "type": "STRING", "mode": "NULLABLE"},
  {"name": "model_version", "type": "STRING", "mode": "NULLABLE"}
]
EOF
}

output "dataset_id" {
  value = google_bigquery_dataset.marketing.dataset_id
}
