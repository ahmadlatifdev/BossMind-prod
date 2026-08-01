"""Slack alerts — never posts to ad platforms."""
from __future__ import annotations

from typing import Any, Dict, Optional

import httpx

from marketing_intel.config import assert_no_ad_writes, get_settings
from marketing_intel.logging_setup import setup_logging

log = setup_logging()


def send_slack_alert(title: str, body: str, extra: Optional[Dict[str, Any]] = None) -> bool:
    assert_no_ad_writes()
    settings = get_settings()
    if not settings.enable_slack_alerts or not settings.slack_webhook_url:
        log.info("slack_skipped title=%s", title)
        return False

    payload = {
        "text": f"*Resumora Mkt Intel — {title}*\n{body}",
        "blocks": [
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": f"*Resumora Marketing Intel*\n*{title}*\n{body}",
                },
            }
        ],
    }
    if extra:
        payload["blocks"].append(
            {
                "type": "context",
                "elements": [{"type": "mrkdwn", "text": str(extra)[:500]}],
            }
        )

    with httpx.Client(timeout=15.0) as client:
        resp = client.post(settings.slack_webhook_url, json=payload)
        resp.raise_for_status()
    log.info("slack_sent title=%s", title)
    return True


def alert_competitor_price_drop(competitor: str, old_price: float, new_price: float) -> bool:
    drop_pct = (old_price - new_price) / max(old_price, 1e-6)
    if drop_pct < 0.05:
        return False
    return send_slack_alert(
        "Competitor price drop",
        f"{competitor}: ${old_price:.0f} → ${new_price:.0f} ({drop_pct:.0%} down). Advisory only — no ad changes.",
    )


def alert_segmentation_shift(message: str) -> bool:
    return send_slack_alert("Segmentation shift", f"{message}\nNo campaign auto-changes applied.")
