"""
Streamlit entry — uses modules/ BigQuery + PricingOptimizer + BrandAnalyzer.
Advisory only; never writes to ad platforms or Stripe.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd
import streamlit as st

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from modules.brand_analyzer import BrandAnalyzer
from modules.pricing_model import PricingOptimizer

st.set_page_config(page_title="Resumora Marketing Intel", layout="wide")
st.title("Resumora Marketing Intelligence")
st.caption("Read-only intelligence layer — social ad campaigns are never modified.")

with st.sidebar:
    st.success("Ad writes: BLOCKED")
    st.info("Gemini: flash-lite")

tab_price, tab_brand, tab_bq = st.tabs(["Pricing", "Brand", "BigQuery"])

with tab_price:
    st.subheader("Price recommendations")
    opt = PricingOptimizer()
    demo = PricingOptimizer.synthesize_demo_frame()
    opt.train(demo)
    st.write(f"Demo train MAE: ${opt.last_mae:.2f}" if opt.last_mae is not None else "")
    seg = st.selectbox(
        "Segment",
        [0, 1, 2],
        format_func=lambda i: ["price_sensitive", "value", "premium"][i],
    )
    ratio = st.slider("Price / competitor ratio", 0.5, 1.5, 1.0, 0.05)
    cr = st.slider("Conversion rate", 0.02, 0.4, 0.1, 0.01)
    pred = opt.predict_optimal_price(
        {
            "price_to_competitor_ratio": ratio,
            "conversion_rate": cr,
            "user_segment_encoded": seg,
            "data_volume": 500,
        }
    )
    st.metric("Recommended price", f"${pred['recommended_price']:.2f}")
    st.metric("Confidence", f"{pred['confidence_score']:.0%}")
    st.warning("Advisory only — does not change live Stripe prices.")

with tab_brand:
    st.subheader("Brand gap (Gemini Flash-Lite)")
    if st.button("Run sample brand analysis"):
        analyzer = BrandAnalyzer()
        report = analyzer.generate_weekly_report(
            {
                "PeerA": "Cheap resumes in 24 hours. Lowest price guarantee. Unlimited revisions.",
                "PeerB": "Executive career coaching and LinkedIn makeovers for senior leaders.",
            }
        )
        st.dataframe(report, use_container_width=True)

with tab_bq:
    st.subheader("BigQuery (optional)")
    st.write("Requires ADC login and terraform-applied tables.")
    if st.button("Try load user_behavior (last 7 days)"):
        try:
            from datetime import date, timedelta

            from modules.bigquery_client import BigQueryClient

            client = BigQueryClient()
            end = date.today()
            start = end - timedelta(days=7)
            df = client.get_user_behavior(start.isoformat(), end.isoformat())
            st.dataframe(df if len(df) else pd.DataFrame({"note": ["No rows yet"]}))
        except Exception as exc:  # noqa: BLE001
            st.error(f"BigQuery unavailable: {exc}")
