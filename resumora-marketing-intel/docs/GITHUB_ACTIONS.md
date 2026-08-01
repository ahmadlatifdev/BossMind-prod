# GitHub Actions / local deploy checklist (Resumora Marketing Intel)

## Local modules (ready)

```
modules/bigquery_client.py
modules/pricing_model.py
modules/brand_analyzer.py
dashboard/app.py
data/our_brand_copy.txt
```

```powershell
cd D:\BossMind\resumora-marketing-intel
gcloud auth application-default login
streamlit run dashboard\app.py
```

## One-time GCP prep (Ahmed)

```bash
# State bucket
gcloud storage buckets create gs://resumora-terraform-state-resumora-live --location=us-central1
gcloud storage buckets update gs://resumora-terraform-state-resumora-live --versioning

# Deployer SA (prefer least privilege — avoid roles/editor if possible)
gcloud iam service-accounts create github-mkt-intel-deployer --display-name="Marketing Intel GitHub Deployer"
# Grant: run.admin, cloudbuild.builds.editor, storage.admin, bigquery.admin,
#        aiplatform.user, cloudscheduler.admin, iam.serviceAccountUser
# Then create key ONLY if Workload Identity Federation is not used yet:
# gcloud iam service-accounts keys create gcp-key.json --iam-account=...
```

## GitHub secrets (BossMind-prod repo)

| Secret | Purpose |
|--------|---------|
| `GCP_PROJECT_ID` | `resumora-live` |
| `GCP_SA_KEY` | Deployer SA JSON (never commit) |
| `GCP_BILLING_ACCOUNT` | Optional budget alerts |
| `SLACK_WEBHOOK_URL` | Incoming webhook for deploy success/failure alerts |

Workflow: `.github/workflows/marketing-intel-deploy.yml`

### Slack setup (deploy notifications)

1. Create a Slack app → **Incoming Webhooks** → ON → add to `#marketing-deploys` (or `#alerts`).
2. Copy the webhook URL (`https://hooks.slack.com/services/...`).
3. GitHub → Settings → Secrets → Actions → `SLACK_WEBHOOK_URL`.
4. Optional local test (do not commit the URL):

```bash
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"🚀 Test message from Resumora Marketing Intel"}' \
  "$SLACK_WEBHOOK_URL"
```

On **main** deploy: Slack gets ✅ with Cloud Run URL, or ❌ with Actions run link.  
PR terraform **plan** stays as a PR comment only (no Slack noise).

## Safety

- No Meta/TikTok/Google Ads campaign APIs
- `AD_PLATFORM_WRITE_ENABLED=false` on Cloud Run
- Do **not** use a public standalone repo if it would expose internal ops; monorepo workflow is preferred
