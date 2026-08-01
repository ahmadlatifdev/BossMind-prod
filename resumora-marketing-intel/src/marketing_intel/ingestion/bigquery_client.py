"""BigQuery helpers — ingest only; never touches ad platform APIs."""
from __future__ import annotations

from pathlib import Path
from typing import Any, Iterable, Optional

import pandas as pd
from google.cloud import bigquery

from marketing_intel.config import assert_no_ad_writes, get_settings
from marketing_intel.logging_setup import setup_logging

log = setup_logging()


class BigQueryClient:
    def __init__(self, project_id: Optional[str] = None) -> None:
        assert_no_ad_writes()
        self.settings = get_settings()
        self.project_id = project_id or self.settings.gcp_project_id
        self.client = bigquery.Client(project=self.project_id)
        self.dataset = self.settings.bq_dataset

    def fq(self, table: str) -> str:
        return f"{self.project_id}.{self.dataset}.{table}"

    def ensure_dataset(self, location: str = "US") -> None:
        ds = bigquery.Dataset(f"{self.project_id}.{self.dataset}")
        ds.location = location
        ds.description = "Resumora marketing intelligence (read-only ads policy)"
        self.client.create_dataset(ds, exists_ok=True)
        log.info("dataset_ready %s", self.dataset)

    def run_sql_file(self, path: str | Path) -> None:
        sql = Path(path).read_text(encoding="utf-8")
        sql = sql.replace("${PROJECT}", self.project_id).replace("${DATASET}", self.dataset)
        for stmt in [s.strip() for s in sql.split(";") if s.strip()]:
            job = self.client.query(stmt)
            job.result()
        log.info("sql_applied %s", path)

    def load_dataframe(
        self,
        df: pd.DataFrame,
        table: str,
        write_disposition: str = "WRITE_APPEND",
    ) -> int:
        table_id = self.fq(table)
        job_config = bigquery.LoadJobConfig(
            write_disposition=write_disposition,
            autodetect=True,
        )
        job = self.client.load_table_from_dataframe(df, table_id, job_config=job_config)
        job.result()
        log.info("loaded_rows table=%s rows=%s", table, len(df))
        return len(df)

    def load_csv(
        self,
        csv_path: str | Path,
        table: str,
        write_disposition: str = "WRITE_APPEND",
    ) -> int:
        df = pd.read_csv(csv_path)
        return self.load_dataframe(df, table, write_disposition=write_disposition)

    def query_df(self, sql: str, params: Optional[Iterable[Any]] = None) -> pd.DataFrame:
        job_config = bigquery.QueryJobConfig()
        if params:
            job_config.query_parameters = list(params)
        return self.client.query(sql, job_config=job_config).to_dataframe()

    def ingest_ga4_export_sample(self, events_df: pd.DataFrame) -> int:
        """Map a GA4-like event export into conversion_events / user_behavior."""
        required = {"event_date", "event_name", "user_pseudo_id"}
        missing = required - set(events_df.columns)
        if missing:
            raise ValueError(f"GA4 frame missing columns: {missing}")
        return self.load_dataframe(events_df, "user_behavioral_events")


def get_client() -> BigQueryClient:
    return BigQueryClient()
