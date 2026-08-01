"""
Minimal HTTP job API for Cloud Scheduler → Cloud Run.
Does NOT write to ad platforms. Also exposes /health.
Streamlit dashboard remains: streamlit run dashboard/dashboard_app.py
"""
from __future__ import annotations

import os
from typing import Any, Dict

from flask import Flask, jsonify

from marketing_intel.config import assert_no_ad_writes
from marketing_intel.logging_setup import setup_logging

log = setup_logging()
app = Flask(__name__)


@app.get("/health")
def health() -> Any:
    return jsonify({"ok": True, "service": "resumora-mkt-intel", "ads_write": False})


@app.post("/api/brand-analysis")
def brand_analysis() -> Any:
    assert_no_ad_writes()
    from marketing_intel.jobs.run_brand_job import main as run

    run()
    return jsonify({"ok": True, "job": "brand-analysis"})


@app.post("/api/competitor-scrape")
def competitor_scrape() -> Any:
    assert_no_ad_writes()
    from marketing_intel.jobs.watch_competitor_prices import main as run

    run()
    return jsonify({"ok": True, "job": "competitor-scrape"})


@app.post("/api/model-retrain")
def model_retrain() -> Any:
    assert_no_ad_writes()
    from marketing_intel.jobs.train_models import main as run

    run()
    return jsonify({"ok": True, "job": "model-retrain"})


@app.get("/")
def index() -> Any:
    return jsonify(
        {
            "service": "resumora-marketing-intel",
            "dashboard": "Run Streamlit locally or set dual-process image",
            "jobs": [
                "POST /api/brand-analysis",
                "POST /api/competitor-scrape",
                "POST /api/model-retrain",
            ],
            "safety": "ad_platform_writes=blocked",
        }
    )


def main() -> None:
    port = int(os.environ.get("PORT", "8080"))
    log.info("job_api_listen port=%s", port)
    app.run(host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
