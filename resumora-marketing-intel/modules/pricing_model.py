"""
Simplified price optimization — RandomForest price elasticity MVP.
Advisory only: does not change Stripe or live resumora.net prices.
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

import numpy as np
import pandas as pd
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error
from sklearn.model_selection import train_test_split


class PricingOptimizer:
    def __init__(self) -> None:
        self.model: Optional[RandomForestRegressor] = None
        self.feature_columns: List[str] = []
        self.last_mae: Optional[float] = None

    def train(self, df: pd.DataFrame) -> RandomForestRegressor:
        """
        Expects columns: competitor_avg_price, historical_price, conversion_rate
        Optional: user_segment_encoded
        """
        frame = df.copy()
        if "competitor_avg_price" not in frame.columns or "historical_price" not in frame.columns:
            raise ValueError("df must include competitor_avg_price and historical_price")
        if "conversion_rate" not in frame.columns:
            frame["conversion_rate"] = 0.1

        frame["price_to_competitor_ratio"] = frame["historical_price"] / (
            frame["competitor_avg_price"] + 0.01
        )

        features = ["price_to_competitor_ratio", "conversion_rate"]
        if "user_segment_encoded" in frame.columns:
            features.append("user_segment_encoded")

        self.feature_columns = features
        x = frame[features]
        y = frame["historical_price"]

        x_train, x_test, y_train, y_test = train_test_split(
            x, y, test_size=0.2, random_state=42
        )
        self.model = RandomForestRegressor(
            n_estimators=50, max_depth=5, random_state=42, n_jobs=-1
        )
        self.model.fit(x_train, y_train)

        self.last_mae = float(mean_absolute_error(y_test, self.model.predict(x_test)))
        return self.model

    def predict_optimal_price(self, segment_data: Dict[str, Any]) -> Dict[str, float]:
        """Returns recommended price and confidence for a given segment."""
        if self.model is None:
            raise ValueError("Model not trained yet.")

        row = [
            segment_data.get("price_to_competitor_ratio", 1.0),
            segment_data.get("conversion_rate", 0.5),
        ]
        if "user_segment_encoded" in self.feature_columns:
            row.append(segment_data.get("user_segment_encoded", 0))

        features = np.array([row])
        predicted_price = float(self.model.predict(features)[0])

        confidence = min(0.95, 0.7 + (float(segment_data.get("data_volume", 0)) / 1000.0))

        return {
            "recommended_price": round(predicted_price, 2),
            "confidence_score": round(confidence, 2),
        }

    @staticmethod
    def synthesize_demo_frame(n: int = 400, seed: int = 42) -> pd.DataFrame:
        """Local demo data when BigQuery is empty."""
        rng = np.random.default_rng(seed)
        historical = rng.choice([19, 49, 79, 110], size=n)
        competitor = rng.uniform(25, 120, size=n)
        return pd.DataFrame(
            {
                "user_segment_encoded": rng.integers(0, 3, size=n),
                "competitor_avg_price": competitor,
                "historical_price": historical,
                "conversion_rate": np.clip(
                    0.25 - 0.0015 * historical + rng.normal(0, 0.02, n), 0.02, 0.4
                ),
            }
        )
