-- Resumora Marketing Intelligence schemas
-- Replace ${PROJECT} / ${DATASET} via client or terraform

CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.user_behavioral_events` (
  event_date DATE,
  event_timestamp TIMESTAMP,
  event_name STRING,
  user_pseudo_id STRING,
  session_id STRING,
  page_location STRING,
  device_category STRING,
  geo_country STRING,
  traffic_source STRING,
  params_json STRING
)
PARTITION BY event_date
CLUSTER BY event_name, user_pseudo_id
OPTIONS (description = 'GA4-like behavioral events — analytics only');

CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.conversion_events` (
  event_date DATE,
  event_timestamp TIMESTAMP,
  user_pseudo_id STRING,
  conversion_name STRING,
  value_usd FLOAT64,
  plan_id STRING,
  currency STRING
)
PARTITION BY event_date
CLUSTER BY plan_id
OPTIONS (description = 'Purchases / leads — not written to ad platforms');

CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.pricing_history` (
  observed_at TIMESTAMP,
  plan_id STRING,
  plan_name STRING,
  price_usd FLOAT64,
  currency STRING,
  source STRING
)
OPTIONS (description = 'Historical Resumora list prices (manual or export)');

CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.competitor_pricing` (
  observed_at TIMESTAMP,
  competitor STRING,
  plan STRING,
  price FLOAT64,
  currency STRING,
  url STRING,
  prev_price FLOAT64
)
OPTIONS (description = 'Manual CSV competitor prices');

CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.ad_export_snapshots` (
  imported_at TIMESTAMP,
  platform STRING,
  campaign_name STRING,
  spend FLOAT64,
  impressions INT64,
  clicks INT64,
  conversions FLOAT64,
  raw_json STRING
)
OPTIONS (description = 'Offline ad CSV archives — READ ONLY; never push to ad APIs');

CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.model_recommendations` (
  generated_at TIMESTAMP,
  segment_id INT64,
  segment_label STRING,
  current_price FLOAT64,
  recommended_price FLOAT64,
  confidence FLOAT64,
  rationale STRING,
  model_version STRING
)
PARTITION BY DATE(generated_at)
OPTIONS (description = 'Advisory price recommendations only');

CREATE TABLE IF NOT EXISTS `${PROJECT}.${DATASET}.brand_gap_reports` (
  generated_at TIMESTAMP,
  model STRING,
  summary STRING,
  gaps_json STRING,
  opportunities_json STRING,
  tone_comparison STRING,
  cached BOOL
)
OPTIONS (description = 'Weekly brand gap reports from Gemini Flash-Lite');
