"""
BigQuery client — marketing intelligence reads/writes.
Uses Application Default Credentials (gcloud auth application-default login).
Never calls Meta/Google Ads campaign APIs.
"""
from __future__ import annotations

import os
from typing import Any, List

import pandas as pd
from google.cloud import bigquery

PROJECT_ID = os.getenv("GOOGLE_CLOUD_PROJECT") or os.getenv("GCP_PROJECT_ID", "resumora-live")
DATASET = os.getenv("BIGQUERY_DATASET") or os.getenv("BQ_DATASET", "resumora_mkt_intel")


class BigQueryClient:
    def __init__(self, project_id: str | None = None, dataset: str | None = None) -> None:
        self.project_id = project_id or PROJECT_ID
        self.dataset = dataset or DATASET
        self.client = bigquery.Client(project=self.project_id)

    def query_to_df(self, sql: str) -> pd.DataFrame:
        """Execute SQL and return results as a Pandas DataFrame."""
        return self.client.query(sql).to_dataframe()

    def insert_rows(self, table_name: str, rows: List[dict[str, Any]]) -> bool:
        """Insert rows into a BigQuery table (for storing new predictions)."""
        table_ref = self.client.dataset(self.dataset).table(table_name)
        errors = self.client.insert_rows_json(table_ref, rows)
        if errors:
            raise RuntimeError(f"BigQuery insert errors: {errors}")
        return True

    def get_user_behavior(self, start_date: str, end_date: str) -> pd.DataFrame:
        """
        Fetch user_behavior rows between dates (ISO YYYY-MM-DD).
        Table schema matches terraform modules/bigquery user_behavior.
        """
        sql = f"""
        SELECT user_id, event_date, user_segment, price_paid, conversion_flag
        FROM `{self.project_id}.{self.dataset}.user_behavior`
        WHERE event_date BETWEEN @start_date AND @end_date
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[
                bigquery.ScalarQueryParameter("start_date", "DATE", start_date),
                bigquery.ScalarQueryParameter("end_date", "DATE", end_date),
            ]
        )
        return self.client.query(sql, job_config=job_config).to_dataframe()

    def get_competitor_pricing(self, days: int = 30) -> pd.DataFrame:
        sql = f"""
        SELECT competitor_name, scrape_date, price, product_tier, prev_price, url
        FROM `{self.project_id}.{self.dataset}.competitor_pricing`
        WHERE scrape_date >= DATE_SUB(CURRENT_DATE(), INTERVAL @days DAY)
        ORDER BY scrape_date DESC
        """
        job_config = bigquery.QueryJobConfig(
            query_parameters=[bigquery.ScalarQueryParameter("days", "INT64", days)]
        )
        return self.client.query(sql, job_config=job_config).to_dataframe()
