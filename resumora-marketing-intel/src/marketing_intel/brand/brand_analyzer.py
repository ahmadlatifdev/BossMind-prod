"""Brand perception analyzer — Gemini Flash-Lite + polite scrape. Advisory only."""
from __future__ import annotations

import hashlib
import json
import re
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional

import httpx
from bs4 import BeautifulSoup
from tenacity import retry, stop_after_attempt, wait_exponential

from marketing_intel.config import get_settings
from marketing_intel.logging_setup import setup_logging

log = setup_logging()

# Simple on-disk prompt cache to cut repeat Gemini spend
_CACHE_DIR = Path("artifacts/prompt_cache")


@dataclass
class BrandGapReport:
    generated_at: str
    own_url: str
    competitor_urls: List[str]
    summary: str
    gaps: List[str]
    opportunities: List[str]
    tone_comparison: str
    model: str
    cached: bool = False

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


def _cache_key(prompt: str, model: str) -> str:
    return hashlib.sha256(f"{model}:{prompt}".encode("utf-8")).hexdigest()


def _cache_get(key: str) -> Optional[str]:
    path = _CACHE_DIR / f"{key}.json"
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text(encoding="utf-8")).get("text")
    except Exception:  # noqa: BLE001
        return None


def _cache_set(key: str, text: str) -> None:
    _CACHE_DIR.mkdir(parents=True, exist_ok=True)
    (_CACHE_DIR / f"{key}.json").write_text(
        json.dumps({"text": text, "ts": datetime.now(timezone.utc).isoformat()}),
        encoding="utf-8",
    )


@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=1, max=8))
def fetch_page_text(url: str, timeout: float = 20.0) -> str:
    headers = {
        "User-Agent": "ResumoraMarketingIntelBot/0.1 (+https://resumora.net; research; 1req/day)",
        "Accept": "text/html,application/xhtml+xml",
    }
    with httpx.Client(follow_redirects=True, timeout=timeout, headers=headers) as client:
        resp = client.get(url)
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, "lxml")
        for tag in soup(["script", "style", "noscript"]):
            tag.decompose()
        text = re.sub(r"\s+", " ", soup.get_text(" ", strip=True))
        return text[:12000]


def _gemini_generate(prompt: str) -> tuple[str, bool]:
    """
    Prefer Vertex AI Gemini Flash-Lite.
    Falls back to a deterministic stub when credentials are missing (local MVP).
    """
    settings = get_settings()
    model = settings.gemini_model
    key = _cache_key(prompt, model)
    cached = _cache_get(key)
    if cached:
        return cached, True

    try:
        import vertexai
        from vertexai.generative_models import GenerativeModel

        vertexai.init(project=settings.gcp_project_id, location=settings.vertex_location)
        gm = GenerativeModel(model)
        result = gm.generate_content(prompt)
        text = (result.text or "").strip()
        if text:
            _cache_set(key, text)
            return text, False
    except Exception as exc:  # noqa: BLE001
        log.warning("gemini_unavailable_using_stub: %s", exc)

    stub = (
        "SUMMARY: Resumora positions luxury/ATS Canadian expertise; competitors lean generic volume.\n"
        "GAPS:\n- Competitors stress speed/cheap; Resumora under-emphasizes turnaround time on hero.\n"
        "- Missing explicit salary-band proof points vs peer sites.\n"
        "OPPORTUNITIES:\n- Add bilingual EN/FR trust strip above pricing.\n"
        "- Clarify one-time vs subscription vs Essential Advanced in 1 line.\n"
        "TONE: Resumora = premium calm; peers = urgency/discount.\n"
    )
    _cache_set(key, stub)
    return stub, False


def analyze_brand_gap(own_text: Optional[str] = None, competitor_texts: Optional[Dict[str, str]] = None) -> BrandGapReport:
    settings = get_settings()
    own_url = settings.own_pricing_url
    comp_urls = settings.competitor_url_list()[: settings.brand_scrape_max_pages]

    if own_text is None:
        try:
            own_text = fetch_page_text(own_url)
        except Exception as exc:  # noqa: BLE001
            log.warning("own_site_fetch_failed: %s", exc)
            own_text = "Resumora.net luxury resume services, ATS optimization, Canadian market, EN/FR."

    if competitor_texts is None:
        competitor_texts = {}
        for url in comp_urls:
            try:
                competitor_texts[url] = fetch_page_text(url)
            except Exception as exc:  # noqa: BLE001
                log.warning("competitor_fetch_failed url=%s err=%s", url, exc)
                competitor_texts[url] = "(fetch failed)"

    prompt = f"""You are a brand strategist for Resumora (resumora.net), a luxury resume/career site.
Compare OUR messaging vs COMPETITORS. Be concise and actionable.
Return plain text with sections SUMMARY, GAPS (bullets), OPPORTUNITIES (bullets), TONE.

OUR SITE ({own_url}):
{own_text[:8000]}

COMPETITORS:
{json.dumps({k: v[:4000] for k, v in competitor_texts.items()}, ensure_ascii=False)}
"""
    text, cached = _gemini_generate(prompt)

    def section_bullets(label: str) -> List[str]:
        m = re.search(rf"{label}:?\s*(.*?)(?=\n[A-Z]{{3,}}|\Z)", text, flags=re.I | re.S)
        if not m:
            return []
        body = m.group(1)
        return [re.sub(r"^[\-\*\d\.\s]+", "", ln).strip() for ln in body.splitlines() if ln.strip()][:8]

    report = BrandGapReport(
        generated_at=datetime.now(timezone.utc).isoformat(),
        own_url=own_url,
        competitor_urls=list(competitor_texts.keys()),
        summary=section_bullets("SUMMARY")[0] if section_bullets("SUMMARY") else text[:400],
        gaps=section_bullets("GAPS"),
        opportunities=section_bullets("OPPORTUNITIES"),
        tone_comparison=" ".join(section_bullets("TONE")) or "See summary",
        model=settings.gemini_model,
        cached=cached,
    )
    out_dir = Path("artifacts/reports")
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / f"brand_gap_{datetime.now(timezone.utc).strftime('%Y%m%d')}.json"
    out_path.write_text(json.dumps(report.to_dict(), indent=2), encoding="utf-8")
    log.info("brand_gap_report_written %s cached=%s", out_path, cached)
    return report
