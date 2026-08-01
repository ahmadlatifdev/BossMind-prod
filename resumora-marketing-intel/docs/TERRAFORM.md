# Terraform cost controls — Resumora Marketing Intelligence

## Apply

```bash
cd D:/BossMind/resumora-marketing-intel/terraform
cp terraform.tfvars.example terraform.tfvars   # edit
gcloud auth application-default login
gcloud config set project resumora-live
terraform init
terraform plan
terraform apply
```

## What gets enforced

| Resource | Cost control |
|----------|----------------|
| Cloud Run | `min_instance_count = 0`, max 3, 1 vCPU / 2Gi |
| Vertex AI | Endpoint only — no always-on prediction nodes |
| BigQuery | DAY partition, clustering, 90d expiration |
| GCS | Nearline@30d → Coldline@90d → Delete@365d |
| Budget | Optional 90%/100% alerts (`enable_budget_alert`) |
| IAM | No Ads Admin / campaign mutate roles |

## Scheduler routes (Cloud Run job API)

- `POST /api/brand-analysis` — daily 06:00
- `POST /api/competitor-scrape` — Mondays 08:00
- `POST /api/model-retrain` — 1st of month 10:00

Timezone default: `America/Toronto`.

## Safety

Terraform injects `AD_PLATFORM_WRITE_ENABLED=false` and `AUTO_APPLY_PRICE_CHANGES=false` into Cloud Run.
Existing social ad campaigns are never modified by this stack.
