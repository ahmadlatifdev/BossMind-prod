"""
Brand analyzer — Gemini Flash-Lite vs competitors.
COST: flash-lite; falls back to stub if Vertex credentials missing.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any, Dict

import pandas as pd

PROJECT_ID = os.getenv("GOOGLE_CLOUD_PROJECT") or os.getenv("GCP_PROJECT_ID", "resumora-live")
LOCATION = os.getenv("REGION") or os.getenv("GCP_REGION", "us-central1")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.0-flash-lite")


class BrandAnalyzer:
    def __init__(self, project_id: str | None = None, location: str | None = None) -> None:
        self.project_id = project_id or PROJECT_ID
        self.location = location or LOCATION
        self.model_name = GEMINI_MODEL
        self._model = None
        self._init_error: str | None = None
        try:
            import vertexai
            from vertexai.generative_models import GenerativeModel

            vertexai.init(project=self.project_id, location=self.location)
            self._model = GenerativeModel(self.model_name)
        except Exception as exc:  # noqa: BLE001 — allow local demo without Vertex
            self._init_error = str(exc)

    def analyze_competitor(self, competitor_website_text: str, our_website_text: str) -> dict:
        """Compare our brand messaging vs a competitor. Returns JSON-shaped dict."""
        prompt = f"""
        You are a brand strategist. Compare the following two brand descriptions for a resume builder.

        OUR BRAND (Resumora / resumora.net):
        {our_website_text[:2000]}

        COMPETITOR:
        {competitor_website_text[:2000]}

        Provide output as JSON with the following keys:
        - "sentiment_score": float (0 to 1, where 1 is most positive towards our brand)
        - "key_themes": list of strings (top 3 unique strengths we have)
        - "raw_analysis": string (brief strategic summary)
        """

        if self._model is None:
            return {
                "sentiment_score": 0.62,
                "key_themes": [
                    "Luxury Canadian ATS positioning",
                    "EN/FR bilingual trust",
                    "Clear plan tiers vs volume discounters",
                ],
                "raw_analysis": (
                    f"Vertex unavailable ({self._init_error}). "
                    "Stub analysis: Resumora reads premium/ATS; competitor text length="
                    f"{len(competitor_website_text)}."
                ),
            }

        try:
            response = self._model.generate_content(prompt)
            clean = (response.text or "").replace("```json", "").replace("```", "").strip()
        except Exception as exc:  # noqa: BLE001
            return {
                "sentiment_score": 0.62,
                "key_themes": [
                    "Luxury Canadian ATS positioning",
                    "EN/FR bilingual trust",
                    "Clear plan tiers vs volume discounters",
                ],
                "raw_analysis": f"Gemini call failed ({exc}); using stub analysis.",
            }

        try:
            return json.loads(clean)
        except json.JSONDecodeError:
            m = re.search(r"\{[\s\S]*\}", clean)
            if m:
                try:
                    return json.loads(m.group(0))
                except json.JSONDecodeError:
                    pass
            return {
                "sentiment_score": 0.5,
                "key_themes": ["parse_fallback"],
                "raw_analysis": clean[:2000],
            }

    def generate_weekly_report(self, competitors: Dict[str, str]) -> pd.DataFrame:
        """Run analysis for multiple competitors and return a DataFrame."""
        brand_path = Path(__file__).resolve().parents[1] / "data" / "our_brand_copy.txt"
        if brand_path.exists():
            our_text = brand_path.read_text(encoding="utf-8")
        else:
            our_text = (
                "Resumora (resumora.net) — luxury resume and career services for the "
                "Canadian market. ATS optimization, executive resumes, EN/FR support."
            )

        rows: list[dict[str, Any]] = []
        for name, text in competitors.items():
            result = self.analyze_competitor(text, our_text)
            rows.append(
                {
                    "brand_name": name,
                    "sentiment_score": result.get("sentiment_score", 0.5),
                    "key_themes": result.get("key_themes", []),
                    "raw_analysis": result.get("raw_analysis", ""),
                }
            )
        return pd.DataFrame(rows)
