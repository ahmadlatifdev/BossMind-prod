"""Cloud Logging + local fallback."""
from __future__ import annotations

import logging
import os
import sys


def setup_logging(level: str | None = None) -> logging.Logger:
    lvl = getattr(logging, (level or os.getenv("LOG_LEVEL", "INFO")).upper(), logging.INFO)
    root = logging.getLogger("marketing_intel")
    if root.handlers:
        root.setLevel(lvl)
        return root

    root.setLevel(lvl)
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(
        logging.Formatter("%(asctime)s %(levelname)s [%(name)s] %(message)s")
    )
    root.addHandler(handler)

    # Optional Cloud Logging when credentials exist
    try:
        import google.cloud.logging as cloud_logging

        client = cloud_logging.Client()
        client.setup_logging(log_level=lvl)
        root.info("cloud_logging_attached")
    except Exception as exc:  # noqa: BLE001 — local MVP ok without GCP
        root.debug("cloud_logging_skipped: %s", exc)

    return root
