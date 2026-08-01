"""Daily brand scrape + weekly gap report job (Cloud Scheduler → Cloud Run Job)."""
from __future__ import annotations

from marketing_intel.alerts.slack_alerts import send_slack_alert
from marketing_intel.brand.brand_analyzer import analyze_brand_gap
from marketing_intel.logging_setup import setup_logging

log = setup_logging()


def main() -> None:
    report = analyze_brand_gap()
    preview = report.summary[:300]
    send_slack_alert(
        "Weekly brand gap ready" if not report.cached else "Brand gap (cached)",
        f"{preview}\nGaps: {len(report.gaps)} | Opportunities: {len(report.opportunities)} | Model: {report.model}",
    )
    log.info("brand_job_done cached=%s gaps=%s", report.cached, len(report.gaps))


if __name__ == "__main__":
    main()
