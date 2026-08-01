"""Unit tests that do not require GCP."""
from marketing_intel.config import Settings
from marketing_intel.cost.estimator import estimate_monthly_cost
from marketing_intel.models.pricing_model import PricingModel, synthesize_training_frame
from marketing_intel.models.segmentation import SegmentationModel, synthesize_users


def test_safety_locks_forced_false(monkeypatch):
    monkeypatch.setenv("AD_PLATFORM_WRITE_ENABLED", "true")
    monkeypatch.setenv("AUTO_APPLY_PRICE_CHANGES", "true")
    s = Settings(_env_file=None)
    assert s.ad_platform_write_enabled is False
    assert s.auto_apply_price_changes is False


def test_train_pricing_synthetic():
    df = synthesize_training_frame(200)
    m = PricingModel()
    metrics = m.train(df)
    assert "mae" in metrics
    recs = m.batch_recommend(df.groupby("segment_id").head(1))
    assert len(recs) >= 1
    assert recs[0].recommended_price > 0


def test_segmentation():
    users = synthesize_users(120)
    seg = SegmentationModel()
    labeled = seg.train(users)
    assert "segment_label" in labeled.columns
    assert labeled["segment_label"].nunique() >= 2


def test_cost_estimator():
    est = estimate_monthly_cost(0.05, 2.0, 0.5, True, False)
    assert est.total_low_usd >= 3
    assert est.gemini_usd < 20
