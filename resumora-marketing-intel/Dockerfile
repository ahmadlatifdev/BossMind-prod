# syntax=docker/dockerfile:1
FROM python:3.11-slim

WORKDIR /app
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8080
ENV AD_PLATFORM_WRITE_ENABLED=false AUTO_APPLY_PRICE_CHANGES=false

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY pyproject.toml .
COPY src ./src
COPY dashboard ./dashboard
COPY samples ./samples
COPY sql ./sql
COPY config ./config

RUN pip install --no-cache-dir -e .

EXPOSE 8080
# Default: job API for Cloud Scheduler. Dashboard: override CMD to streamlit.
CMD ["gunicorn", "-b", "0.0.0.0:8080", "-w", "1", "--timeout", "600", "marketing_intel.api.app:app"]
