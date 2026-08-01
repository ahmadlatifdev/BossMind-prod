"""
Resumora Marketing Intelligence Dashboard
Advisory only — does NOT modify ads, Stripe, or live prices.
"""
from __future__ import annotations

import json
from pathlib import Path

import pandas as pd
import streamlit as st

from marketing_intel.config import get_settings
from marketing_intel.cost.estimator import bigquery_slot_recommendation, estimate_monthly_cost
from marketing_intel.models.pricing_model import PricingModel, synthesize_training_frame
from marketing_intel.models.segmentation import SEGMENT_LABELS

st.set_page_config(
    page_title="Resumora Marketing Intel",
    page_icon="📊",
    layout="wide",
)

st.title("Resumora Marketing Intelligence")
st.caption(
    "Standalone intelligence layer for resumora.net — **read-only**. "
    "Never writes to ad platforms or auto-applies Stripe prices."
)

settings = get_settings()

with st.sidebar:
    st.header("Safety locks")
    st.success("Ad platform writes: BLOCKED")
    st.success("Auto price apply: BLOCKED")
    st.info(f"Project: `{settings.gcp_project_id}`")
    st.info(f"Gemini model: `{settings.gemini_model}`")
    st.markdown("[Open resumora.net/pricing](https://resumora.net/pricing)")

tab_rec, tab_comp, tab_brand, tab_whatif, tab_cost = st.tabs(
    [
        "Pricing recommendations",
        "Competitor alerts",
        "Brand perception",
        "What-if simulator",
        "Cost estimator",
    ]
)

recs_path = Path("artifacts/reports/daily_price_recommendations.json")
brand_files = sorted(Path("artifacts/reports").glob("brand_gap_*.json")) if Path("artifacts/reports").exists() else []

with tab_rec:
    st.subheader("Daily pricing recommendations (batch model)")
    if recs_path.exists():
        recs = json.loads(recs_path.read_text(encoding="utf-8"))
        df = pd.DataFrame(recs)
        if "segment_id" in df.columns:
            df["segment"] = df["segment_id"].map(lambda i: SEGMENT_LABELS.get(int(i), str(i)))
        st.dataframe(df, use_container_width=True)
        st.caption("Confidence is model-derived; human approval required before any live price change.")
    else:
        st.warning("No recommendations yet. Run: `python -m marketing_intel.jobs.train_models`")
        if st.button("Train MVP models now (synthetic data)"):
            from marketing_intel.jobs.train_models import main as train_main

            train_main()
            st.rerun()

with tab_comp:
    st.subheader("Competitor price watch")
    csv_path = Path(settings.sample_csv_dir) / "competitor_prices.csv"
    if csv_path.exists():
        cdf = pd.read_csv(csv_path)
        st.dataframe(cdf, use_container_width=True)
        if "prev_price" in cdf.columns and "price" in cdf.columns:
            drops = cdf[cdf["price"] < cdf["prev_price"] * 0.95]
            if len(drops):
                st.error(f"{len(drops)} competitor price drop(s) ≥5%")
                st.dataframe(drops, use_container_width=True)
            else:
                st.success("No ≥5% drops in current snapshot")
        else:
            st.info("Add a `prev_price` column to enable drop alerts.")
    else:
        st.warning(f"Missing {csv_path}")

with tab_brand:
    st.subheader("Brand gap trends")
    if brand_files:
        latest = json.loads(brand_files[-1].read_text(encoding="utf-8"))
        st.write(f"**Generated:** {latest.get('generated_at')} | **Model:** {latest.get('model')} | **Cached:** {latest.get('cached')}")
        st.write(latest.get("summary"))
        c1, c2 = st.columns(2)
        with c1:
            st.markdown("**Gaps**")
            for g in latest.get("gaps") or []:
                st.write(f"- {g}")
        with c2:
            st.markdown("**Opportunities**")
            for o in latest.get("opportunities") or []:
                st.write(f"- {o}")
        st.markdown(f"**Tone:** {latest.get('tone_comparison')}")
    else:
        st.info("No brand reports yet. Run: `python -m marketing_intel.jobs.run_brand_job`")

with tab_whatif:
    st.subheader("What-if pricing simulation")
    st.caption("Uses the batch RF model if trained; otherwise trains a quick synthetic model in-memory.")
    segment = st.selectbox("Segment", options=list(SEGMENT_LABELS.items()), format_func=lambda x: f"{x[0]} — {x[1]}")
    current = st.slider("Current price (USD)", 9, 150, 49)
    competitor = st.slider("Competitor avg price", 15, 150, 59)
    sessions = st.slider("Sessions (7d)", 1, 50, 12)

    model = PricingModel()
    artifact = Path(settings.model_artifact_dir) / "pricing_rf.joblib"
    if artifact.exists():
        model.load()
    else:
        model.train(synthesize_training_frame(400))

    row = pd.Series(
        {
            "segment_id": segment[0],
            "sessions_7d": sessions,
            "pageviews_pricing_7d": max(1, sessions // 3),
            "bounce_rate": 0.4,
            "device_mobile": 1,
            "geo_ca": 1,
            "competitor_avg_price": competitor,
            "current_price": current,
            "conversion_rate": 0.08,
        }
    )
    grid = list(range(19, 121, 10))
    rec = model.recommend_for_row(row, price_grid=grid)
    st.metric("Recommended price", f"${rec.recommended_price:.0f}", delta=f"conf {rec.confidence:.0%}")
    st.write(rec.rationale)
    st.warning("Simulation only — does not change resumora.net or Stripe.")

with tab_cost:
    st.subheader("Monthly cost estimator")
    bq = st.number_input("BigQuery TiB queried / month", 0.0, 5.0, 0.05, 0.01)
    gin = st.number_input("Gemini input million tokens / month", 0.0, 50.0, 2.0, 0.1)
    gout = st.number_input("Gemini output million tokens / month", 0.0, 20.0, 0.5, 0.1)
    flash = st.checkbox("Use Flash-Lite (recommended)", True)
    always = st.checkbox("Cloud Run always-on", False)
    est = estimate_monthly_cost(bq, gin, gout, flash, always)
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("BigQuery", f"${est.bigquery_usd}")
    c2.metric("Gemini", f"${est.gemini_usd}")
    c3.metric("Cloud Run", f"${est.cloud_run_usd}")
    c4.metric("Range", f"${est.total_low_usd}–${est.total_high_usd}")
    st.write(est.notes)
    st.info(bigquery_slot_recommendation(bq / 30 if bq else 0.001))
