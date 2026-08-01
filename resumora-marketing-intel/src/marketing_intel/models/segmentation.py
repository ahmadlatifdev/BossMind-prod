"""Customer segmentation — price-sensitive vs premium (batch sklearn)."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Dict, List

import joblib
import numpy as np
import pandas as pd
from sklearn.cluster import KMeans
from sklearn.preprocessing import StandardScaler

from marketing_intel.config import get_settings
from marketing_intel.logging_setup import setup_logging

log = setup_logging()

SEG_FEATURES = [
    "sessions_7d",
    "pageviews_pricing_7d",
    "bounce_rate",
    "device_mobile",
    "geo_ca",
    "avg_order_value",
    "time_on_pricing_sec",
]

SEGMENT_LABELS = {
    0: "price_sensitive",
    1: "value_seeker",
    2: "premium",
}


class SegmentationModel:
    def __init__(self, n_clusters: int = 3) -> None:
        self.n_clusters = n_clusters
        self.scaler = StandardScaler()
        self.kmeans = KMeans(n_clusters=n_clusters, random_state=42, n_init=10)
        self.label_map: Dict[int, str] = dict(SEGMENT_LABELS)

    def _dir(self) -> Path:
        p = Path(get_settings().model_artifact_dir)
        p.mkdir(parents=True, exist_ok=True)
        return p

    def train(self, df: pd.DataFrame) -> pd.DataFrame:
        x = df[SEG_FEATURES].fillna(0)
        xs = self.scaler.fit_transform(x)
        labels = self.kmeans.fit_predict(xs)
        # Order clusters by avg_order_value so 0=sensitive, 2=premium
        aov = df.assign(_k=labels).groupby("_k")["avg_order_value"].mean().sort_values()
        remap = {old: new for new, old in enumerate(aov.index.tolist())}
        mapped = np.array([remap[i] for i in labels])
        out = df.copy()
        out["segment_id"] = mapped
        out["segment_label"] = out["segment_id"].map(self.label_map)
        log.info("segmentation_trained counts=%s", out["segment_label"].value_counts().to_dict())
        return out

    def save(self) -> Path:
        path = self._dir() / "segmentation_kmeans.joblib"
        joblib.dump(
            {"scaler": self.scaler, "kmeans": self.kmeans, "labels": self.label_map},
            path,
        )
        (self._dir() / "segment_labels.json").write_text(json.dumps(self.label_map, indent=2))
        return path

    def load(self) -> None:
        blob = joblib.load(self._dir() / "segmentation_kmeans.joblib")
        self.scaler = blob["scaler"]
        self.kmeans = blob["kmeans"]
        self.label_map = blob.get("labels", SEGMENT_LABELS)

    def predict(self, df: pd.DataFrame) -> pd.DataFrame:
        x = df[SEG_FEATURES].fillna(0)
        xs = self.scaler.transform(x)
        raw = self.kmeans.predict(xs)
        out = df.copy()
        out["segment_id"] = raw
        out["segment_label"] = out["segment_id"].map(lambda i: self.label_map.get(int(i), f"seg_{i}"))
        return out


def synthesize_users(n: int = 600, seed: int = 3) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    # Mix three latent personas
    persona = rng.choice([0, 1, 2], size=n, p=[0.4, 0.35, 0.25])
    sessions = np.where(persona == 2, rng.integers(5, 40, n), rng.integers(1, 20, n))
    pricing_views = np.where(persona == 0, rng.integers(3, 20, n), rng.integers(0, 10, n))
    bounce = np.where(persona == 0, rng.uniform(0.4, 0.85, n), rng.uniform(0.15, 0.5, n))
    aov = np.where(
        persona == 2,
        rng.uniform(70, 130, n),
        np.where(persona == 1, rng.uniform(40, 70, n), rng.uniform(15, 40, n)),
    )
    return pd.DataFrame(
        {
            "user_pseudo_id": [f"u{i}" for i in range(n)],
            "sessions_7d": sessions,
            "pageviews_pricing_7d": pricing_views,
            "bounce_rate": bounce,
            "device_mobile": rng.integers(0, 2, n),
            "geo_ca": rng.integers(0, 2, n),
            "avg_order_value": aov,
            "time_on_pricing_sec": rng.integers(5, 300, n),
        }
    )


def segment_shift_alert(prev_counts: Dict[str, int], curr_counts: Dict[str, int], threshold: float = 0.15) -> List[str]:
    alerts = []
    for label, curr in curr_counts.items():
        prev = prev_counts.get(label, curr)
        if prev == 0:
            continue
        delta = abs(curr - prev) / prev
        if delta >= threshold:
            alerts.append(f"Segmentation shift: {label} {prev} → {curr} ({delta:.0%})")
    return alerts
