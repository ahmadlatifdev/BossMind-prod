"""Weekly Google Sheets export — recommendations only."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, List

from marketing_intel.config import get_settings
from marketing_intel.logging_setup import setup_logging

log = setup_logging()


def export_weekly_report(rows: List[Dict[str, Any]]) -> bool:
    """
    Append rows to a Google Sheet if ENABLE_SHEETS_EXPORT=true.
    Uses Application Default Credentials / service account.
    """
    settings = get_settings()
    if not settings.enable_sheets_export or not settings.google_sheets_spreadsheet_id:
        log.info("sheets_export_skipped")
        return False

    from googleapiclient.discovery import build
    from google.auth import default

    creds, _ = default(scopes=["https://www.googleapis.com/auth/spreadsheets"])
    service = build("sheets", "v4", credentials=creds, cache_discovery=False)

    header = ["generated_at", "segment", "current_price", "recommended_price", "confidence", "notes"]
    values = [header]
    ts = datetime.now(timezone.utc).isoformat()
    for r in rows:
        values.append(
            [
                ts,
                str(r.get("segment", "")),
                r.get("current_price", ""),
                r.get("recommended_price", ""),
                r.get("confidence", ""),
                str(r.get("notes", ""))[:500],
            ]
        )

    service.spreadsheets().values().append(
        spreadsheetId=settings.google_sheets_spreadsheet_id,
        range="Weekly!A1",
        valueInputOption="USER_ENTERED",
        insertDataOption="INSERT_ROWS",
        body={"values": values},
    ).execute()
    log.info("sheets_export_ok rows=%s", len(rows))
    return True
