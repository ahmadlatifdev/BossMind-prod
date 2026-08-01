"""Settings — never enable ad-platform writes."""
from functools import lru_cache
from typing import List

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    gcp_project_id: str = "resumora-live"
    gcp_region: str = "us-central1"
    bq_dataset: str = "resumora_mkt_intel"
    gcs_bucket_raw: str = "resumora-mkt-intel-raw"
    gcs_bucket_models: str = "resumora-mkt-intel-models"

    vertex_location: str = "us-central1"
    gemini_model: str = "gemini-2.0-flash-lite"
    gemini_use_batch: bool = True
    brand_scrape_max_pages: int = 8

    own_site_url: str = "https://resumora.net"
    own_pricing_url: str = "https://resumora.net/pricing"
    competitor_urls: str = ""

    slack_webhook_url: str = ""
    enable_slack_alerts: bool = False
    google_sheets_spreadsheet_id: str = ""
    enable_sheets_export: bool = False

    # Hard safety locks
    ad_platform_write_enabled: bool = False
    auto_apply_price_changes: bool = False
    stripe_mode_touch_enabled: bool = False

    sample_csv_dir: str = "./samples/csv"
    model_artifact_dir: str = "./artifacts/models"
    log_level: str = "INFO"

    @field_validator("ad_platform_write_enabled", "auto_apply_price_changes", "stripe_mode_touch_enabled")
    @classmethod
    def force_false(cls, v: bool) -> bool:
        """MVP refuses write-back flags even if mis-set in env."""
        return False

    def competitor_url_list(self) -> List[str]:
        return [u.strip() for u in self.competitor_urls.split(",") if u.strip()]

    @property
    def bq_table(self):
        def fq(table: str) -> str:
            return f"{self.gcp_project_id}.{self.bq_dataset}.{table}"

        return fq


@lru_cache
def get_settings() -> Settings:
    return Settings()


def assert_no_ad_writes() -> None:
    s = get_settings()
    if s.ad_platform_write_enabled or s.auto_apply_price_changes:
        raise RuntimeError("AD_WRITE_BLOCKED: marketing intel must remain read-only for ads/pricing apply")
