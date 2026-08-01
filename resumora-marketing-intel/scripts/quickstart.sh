#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Resumora Marketing Intel quickstart =="
echo "Safety: AD writes DISABLED"

python3.11 -m venv .venv || python3 -m venv .venv
# shellcheck disable=SC1091
source .venv/bin/activate
pip install -U pip
pip install -r requirements.txt
pip install -e .

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created .env from .env.example — edit GCP + Slack as needed"
fi

mkdir -p artifacts/models artifacts/reports secrets
python -m marketing_intel.jobs.train_models
python -m marketing_intel.jobs.watch_competitor_prices || true

echo ""
echo "Train OK. Start dashboard:"
echo "  streamlit run dashboard/dashboard_app.py"
echo ""
echo "Brand job (needs network / Vertex optional):"
echo "  python -m marketing_intel.jobs.run_brand_job"
