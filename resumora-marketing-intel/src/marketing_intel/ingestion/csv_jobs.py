"""CSV / GA4 file ingestion jobs (offline files only — no ad API calls)."""
from __future__ import annotations

from pathlib import Path

import typer

from marketing_intel.config import get_settings
from marketing_intel.ingestion.bigquery_client import get_client
from marketing_intel.logging_setup import setup_logging

app = typer.Typer(add_completion=False)
log = setup_logging()


@app.command()
def ingest_competitor_prices(csv_path: str | None = None) -> None:
    """Load competitor pricing CSV into BigQuery."""
    settings = get_settings()
    path = Path(csv_path or Path(settings.sample_csv_dir) / "competitor_prices.csv")
    client = get_client()
    client.ensure_dataset()
    n = client.load_csv(path, "competitor_pricing", write_disposition="WRITE_APPEND")
    log.info("competitor_prices_ingested rows=%s file=%s", n, path)


@app.command()
def ingest_ad_export_csv(csv_path: str) -> None:
    """
    Import a *downloaded* ad-platform CSV for analysis only.
    Does NOT call Meta/Google Ads APIs and never writes campaigns.
    """
    client = get_client()
    client.ensure_dataset()
    n = client.load_csv(csv_path, "ad_export_snapshots", write_disposition="WRITE_APPEND")
    log.info("ad_export_snapshot_ingested rows=%s (read-only archive)", n)


@app.command()
def ingest_pricing_history(csv_path: str | None = None) -> None:
    settings = get_settings()
    path = Path(csv_path or Path(settings.sample_csv_dir) / "pricing_history.csv")
    client = get_client()
    client.ensure_dataset()
    n = client.load_csv(path, "pricing_history", write_disposition="WRITE_APPEND")
    log.info("pricing_history_ingested rows=%s", n)


if __name__ == "__main__":
    app()
