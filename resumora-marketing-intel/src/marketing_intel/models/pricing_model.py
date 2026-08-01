"""Batch price optimization — RandomForest / XGBoost. No online Vertex endpoints."""
from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

import joblib
import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_absolute_error, r2_score

from marketing_intel.config import get_settings
from marketing_intel.logging_setup import setup_logging

log = setup_logging()

FEATURE_COLS = [
    "segment_id",
    "sessions_7d",
    "pageviews_pricing_7d",
    "bounce_rate",
    "device_mobile",
    "geo_ca",
    "competitor_avg_price",
    "current_price",
]


@dataclass
class PriceRecommendation:
    segment_id: int
    current_price: float
    recommended_price: float
    expected_conversion_lift: float
    confidence: float
    rationale: str

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


class PricingModel:
    """
    MVP: predict conversion_rate from features including price,
    then search a small price grid for max expected revenue per segment.
    Train/predict in batch on Cloud Run or laptop — not Vertex online endpoints.
    """

    def __init__(self) -> None:
        self.model: Optional[RandomForestRegressor] = None
        self.metrics: Dict[str, float] = {}

    def _artifact_dir(self) -> Path:
        p = Path(get_settings().model_artifact_dir)
        p.mkdir(parents=True, exist_ok=True)
        return p

    def train(self, df: pd.DataFrame, target_col: str = "conversion_rate") -> Dict[str, float]:
        missing = set(FEATURE_COLS + [target_col]) - set(df.columns)
        if missing:
            raise ValueError(f"training frame missing: {missing}")

        x = df[FEATURE_COLS]
        y = df[target_col]
        x_train, x_test, y_train, y_test = train_test_split(x, y, test_size=0.2, random_state=42)

        self.model = RandomForestRegressor(
            n_estimators=120,
            max_depth=8,
            min_samples_leaf=5,
            random_state=42,
            n_jobs=-1,
        )
        self.model.fit(x_train, y_train)
        pred = self.model.predict(x_test)
        self.metrics = {
            "mae": float(mean_absolute_error(y_test, pred)),
            "r2": float(r2_score(y_test, pred)),
            "n_train": float(len(x_train)),
        }
        log.info("pricing_model_trained %s", self.metrics)
        return self.metrics

    def save(self, name: str = "pricing_rf.joblib") -> Path:
        if self.model is None:
            raise RuntimeError("model not trained")
        path = self._artifact_dir() / name
        joblib.dump({"model": self.model, "features": FEATURE_COLS, "metrics": self.metrics}, path)
        (self._artifact_dir() / "pricing_metrics.json").write_text(json.dumps(self.metrics, indent=2))
        return path

    def load(self, name: str = "pricing_rf.joblib") -> None:
        path = self._artifact_dir() / name
        blob = joblib.load(path)
        self.model = blob["model"]
        self.metrics = blob.get("metrics", {})

    def recommend_for_row(
        self,
        row: pd.Series,
        price_grid: Optional[List[float]] = None,
    ) -> PriceRecommendation:
        if self.model is None:
            raise RuntimeError("model not loaded")
        grid = price_grid or [19, 29, 39, 49, 59, 79, 99, 110]
        base = row[FEATURE_COLS].copy()
        current = float(row.get("current_price", 49))
        best_price = current
        best_score = -1.0
        best_cr = 0.0
        scores = []

        for price in grid:
            feat = base.copy()
            feat["current_price"] = price
            cr = float(self.model.predict(pd.DataFrame([feat]))[0])
            cr = max(0.0, min(1.0, cr))
            # expected revenue proxy
            score = cr * price
            scores.append(score)
            if score > best_score:
                best_score = score
                best_price = float(price)
                best_cr = cr

        # confidence from relative score spread
        spread = float(np.std(scores) / (np.mean(scores) + 1e-6))
        confidence = float(max(0.35, min(0.95, 0.55 + (1.0 - min(spread, 1.0)) * 0.35)))
        lift = (best_cr * best_price) / max(current * float(row.get("conversion_rate", best_cr) or best_cr), 1e-6) - 1.0

        return PriceRecommendation(
            segment_id=int(row.get("segment_id", 0)),
            current_price=current,
            recommended_price=best_price,
            expected_conversion_lift=float(lift),
            confidence=confidence,
            rationale=(
                f"Batch RF search over {len(grid)} price points; "
                f"max expected revenue proxy at ${best_price:.0f}."
            ),
        )

    def batch_recommend(self, df: pd.DataFrame) -> List[PriceRecommendation]:
        return [self.recommend_for_row(row) for _, row in df.iterrows()]


def synthesize_training_frame(n: int = 800, seed: int = 7) -> pd.DataFrame:
    """Local MVP synthetic data when GA4 export is not yet wired."""
    rng = np.random.default_rng(seed)
    segment = rng.integers(0, 3, size=n)
    current_price = rng.choice([19, 49, 79, 110], size=n)
    sessions = rng.integers(1, 40, size=n)
    pricing_views = rng.integers(0, 15, size=n)
    bounce = rng.uniform(0.2, 0.8, size=n)
    mobile = rng.integers(0, 2, size=n)
    geo_ca = rng.integers(0, 2, size=n)
    competitor = rng.uniform(25, 120, size=n)

    # latent: premium segment (2) tolerates higher price; segment 0 is price-sensitive
    sensitivity = np.where(segment == 0, 1.4, np.where(segment == 1, 1.0, 0.6))
    logit = (
        -1.2
        - 0.025 * current_price * sensitivity
        + 0.03 * sessions
        + 0.04 * pricing_views
        - 0.8 * bounce
        + 0.1 * geo_ca
        + 0.002 * (competitor - current_price)
    )
    cr = 1 / (1 + np.exp(-logit))
    cr = np.clip(cr + rng.normal(0, 0.02, size=n), 0.01, 0.6)

    return pd.DataFrame(
        {
            "segment_id": segment,
            "sessions_7d": sessions,
            "pageviews_pricing_7d": pricing_views,
            "bounce_rate": bounce,
            "device_mobile": mobile,
            "geo_ca": geo_ca,
            "competitor_avg_price": competitor,
            "current_price": current_price,
            "conversion_rate": cr,
        }
    )


# Optional XGBoost path when installed and preferred
def train_xgboost_if_available(df: pd.DataFrame, target_col: str = "conversion_rate"):
    try:
        from xgboost import XGBRegressor
    except ImportError:
        log.warning("xgboost_unavailable_falling_back_rf")
        m = PricingModel()
        m.train(df, target_col=target_col)
        return m

    x = df[FEATURE_COLS]
    y = df[target_col]
    model = XGBRegressor(
        n_estimators=150,
        max_depth=5,
        learning_rate=0.08,
        subsample=0.9,
        colsample_bytree=0.9,
        objective="reg:squarederror",
        random_state=42,
    )
    model.fit(x, y)
    wrap = PricingModel()
    wrap.model = model  # type: ignore[assignment]
    wrap.metrics = {"backend": 1.0, "n_train": float(len(df))}
    return wrap
