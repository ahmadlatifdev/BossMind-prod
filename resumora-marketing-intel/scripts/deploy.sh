#!/usr/bin/env bash
# Deploy cost-optimized Terraform for Resumora Marketing Intelligence.
# Never enables ad-platform writes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/terraform"

PROJECT_ID="${GCP_PROJECT_ID:-resumora-live}"
REGION="${GCP_REGION:-us-central1}"
IMAGE="${DASHBOARD_IMAGE:-${CLOUD_RUN_IMAGE:-}}"

echo "== Terraform deploy =="
echo "project=$PROJECT_ID region=$REGION"
echo "AD_PLATFORM_WRITE_ENABLED remains false"

terraform init -upgrade

TF_VARS=(
  -var="project_id=${PROJECT_ID}"
  -var="region=${REGION}"
  -var="cloud_run_image=${IMAGE}"
)

if [[ -f terraform.tfvars ]]; then
  echo "Using terraform.tfvars"
  terraform plan
  terraform apply -auto-approve
else
  echo "No terraform.tfvars — applying with CLI vars (budget alert off)"
  terraform plan "${TF_VARS[@]}" -var="enable_budget_alert=false" -var="billing_account_id="
  terraform apply -auto-approve "${TF_VARS[@]}" -var="enable_budget_alert=false" -var="billing_account_id="
fi

echo ""
echo "Verify scale-to-zero (after image deploy):"
echo "  gcloud run services describe resumora-mkt-intel-dash --region=${REGION} --project=${PROJECT_ID} --format='yaml(spec.template.scaling)'"
echo "Done."
