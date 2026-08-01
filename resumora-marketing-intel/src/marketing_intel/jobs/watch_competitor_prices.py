"""Compare latest competitor CSV snapshot vs previous — Slack if drop."""
from __future__ import annotations

from pathlib import Path

import pandas as pd

from marketing_intel.alerts.slack_alerts import alert_competitor_price_drop
from marketing_intel.config import get_settings
from marketing_intel.logging_setup import setup_logging

log = setup_logging()


def main() -> None:
    settings = get_settings()
    path = Path(settings.sample_csv_dir) / "competitor_prices.csv"
    if not path.exists():
        log.warning("no_competitor_csv")
        return
    df = pd.read_csv(path)
    # Expect columns: competitor, plan, price, observed_at
    if not {"competitor", "price"}.issubset(df.columns):
        raise SystemExit("competitor_prices.csv needs competitor,price columns")

    # Simple demo: if a prev_price column exists, alert on drops
    if "prev_price" in df.columns:
        for _, row in df.iterrows():
            alert_competitor_price_drop(
                str(row["competitor"]),
                float(row["prev_price"]),
                float(row["price"]),
            )
    else:
        log.info("competitor_watch_ok rows=%s (add prev_price column for drop alerts)", len(df))


if __name__ == "__main__":
    main()
