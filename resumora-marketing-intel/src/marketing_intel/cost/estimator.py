"""Rough monthly cost estimator for the dashboard."""
from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Dict


@dataclass
class CostEstimate:
    bigquery_usd: float
    gemini_usd: float
    cloud_run_usd: float
    storage_scheduler_usd: float
    total_low_usd: float
    total_high_usd: float
    notes: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


def estimate_monthly_cost(
    bq_tib_queried: float = 0.05,
    gemini_input_mtok: float = 2.0,
    gemini_output_mtok: float = 0.5,
    use_flash_lite: bool = True,
    cloud_run_always_on: bool = False,
) -> CostEstimate:
    """
    Order-of-magnitude estimator (USD). Not a quote.
    Flash-Lite approx: $0.10 / $0.40 per 1M tokens (illustrative).
    Flash approx: $0.30 / $2.50 per 1M tokens.
    BQ on-demand ~$6.25 / TiB after free tier (simplified).
    """
    bq = max(0.0, (bq_tib_queried - 1.0)) * 6.25  # first 1 TiB/mo free-ish simplification
    if bq_tib_queried <= 1.0:
        bq = min(15.0, bq_tib_queried * 2.5)  # small projects often $2–15

    if use_flash_lite:
        gemini = gemini_input_mtok * 0.10 + gemini_output_mtok * 0.40
    else:
        gemini = gemini_input_mtok * 0.30 + gemini_output_mtok * 2.50

    run = 18.0 if cloud_run_always_on else 2.0
    other = 1.0

    total_low = max(3.0, bq * 0.3 + gemini * 0.5 + 0.5)
    total_high = bq + gemini + run + other + 20.0

    return CostEstimate(
        bigquery_usd=round(bq, 2),
        gemini_usd=round(gemini, 2),
        cloud_run_usd=round(run, 2),
        storage_scheduler_usd=round(other, 2),
        total_low_usd=round(total_low, 2),
        total_high_usd=round(total_high, 2),
        notes=(
            "Batch ML + Flash-Lite + Cloud Run free tier keeps MVP near $3–15; "
            "Pro models / always-on Run push toward ~$78."
        ),
    )


def bigquery_slot_recommendation(daily_tib: float) -> str:
    if daily_tib < 0.02:
        return "Stay on on-demand (no slot reservation). Partition tables by date; avoid SELECT *."
    if daily_tib < 0.2:
        return "Still prefer on-demand. Consider 100 flex slots only if query concurrency spikes."
    return "Evaluate 500 flex slots vs on-demand with a 7-day cost comparison before committing."
