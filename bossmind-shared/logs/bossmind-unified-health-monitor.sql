CREATE TABLE IF NOT EXISTS bossmind_health_events (
    id BIGSERIAL PRIMARY KEY,
    project_scope TEXT NOT NULL,
    event_type TEXT NOT NULL,
    status TEXT NOT NULL,
    event_data JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO bossmind_health_events (
    project_scope,
    event_type,
    status,
    event_data
)
VALUES (
    'all_projects',
    'unified_health_monitor',
    'HEALTHY',
    '{
    "timestamp":  "2026-05-03T01:52:53",
    "step":  "Step #14",
    "layer":  "BossMind Unified Health Monitor",
    "scope":  "All 5 projects",
    "overall_status":  "HEALTHY",
    "validation_scheduler":  "Ready",
    "validation_layer":  "LOCKED_ACTIVE",
    "predictive_risk":  "LOW",
    "health_monitor":  "ACTIVE",
    "results":  [
                    {
                        "project":  "bossmind-resumora",
                        "path":  "D:\\BossMind\\bossmind-resumora",
                        "folder_exists":  true,
                        "missing_items":  [

                                          ],
                        "health_status":  "HEALTHY",
                        "checked_at":  "2026-05-03T01:52:50"
                    },
                    {
                        "project":  "bossmind-elegancyart",
                        "path":  "D:\\BossMind\\bossmind-elegancyart",
                        "folder_exists":  true,
                        "missing_items":  [

                                          ],
                        "health_status":  "HEALTHY",
                        "checked_at":  "2026-05-03T01:52:50"
                    },
                    {
                        "project":  "bossmind-ai-video-generator",
                        "path":  "D:\\BossMind\\bossmind-ai-video-generator",
                        "folder_exists":  true,
                        "missing_items":  [

                                          ],
                        "health_status":  "HEALTHY",
                        "checked_at":  "2026-05-03T01:52:50"
                    },
                    {
                        "project":  "bossmind-tiktok-ai",
                        "path":  "D:\\BossMind\\bossmind-tiktok-ai",
                        "folder_exists":  true,
                        "missing_items":  [

                                          ],
                        "health_status":  "HEALTHY",
                        "checked_at":  "2026-05-03T01:52:50"
                    },
                    {
                        "project":  "bossmind-global-stock",
                        "path":  "D:\\BossMind\\bossmind-global-stock",
                        "folder_exists":  true,
                        "missing_items":  [

                                          ],
                        "health_status":  "HEALTHY",
                        "checked_at":  "2026-05-03T01:52:50"
                    }
                ]
}'::jsonb
);
