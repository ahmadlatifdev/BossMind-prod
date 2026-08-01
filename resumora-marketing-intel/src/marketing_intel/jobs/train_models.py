"""Train segmentation + pricing locally / on Cloud Run batch (no online endpoints)."""
from __future__ import annotations

import json
from pathlib import Path

from marketing_intel.logging_setup import setup_logging
from marketing_intel.models.pricing_model import PricingModel, synthesize_training_frame
from marketing_intel.models.segmentation import SegmentationModel, synthesize_users

log = setup_logging()


def main() -> None:
    users = synthesize_users(600)
    seg = SegmentationModel()
    labeled = seg.train(users)
    seg.save()

    # Join segment onto synthetic conversion frame
    train = synthesize_training_frame(800)
    # align segment distribution
    train["segment_id"] = labeled["segment_id"].sample(n=len(train), replace=True).to_numpy()

    pricing = PricingModel()
    metrics = pricing.train(train)
    path = pricing.save()

    recs = pricing.batch_recommend(train.groupby("segment_id").head(1))
    out = Path("artifacts/reports")
    out.mkdir(parents=True, exist_ok=True)
    (out / "daily_price_recommendations.json").write_text(
        json.dumps([r.to_dict() for r in recs], indent=2),
        encoding="utf-8",
    )
    log.info("train_complete metrics=%s artifact=%s recs=%s", metrics, path, len(recs))


if __name__ == "__main__":
    main()
