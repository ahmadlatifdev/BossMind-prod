CREATE TABLE IF NOT EXISTS bossmind_performance_events (
    id BIGSERIAL PRIMARY KEY,
    project_scope TEXT NOT NULL,
    event_type TEXT NOT NULL,
    status TEXT NOT NULL,
    event_data JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO bossmind_performance_events (
    project_scope,
    event_type,
    status,
    event_data
)
VALUES (
    'all_projects',
    'performance_profiler',
    'ACTIVE',
    '{
    "timestamp":  "2026-05-03T01:34:28",
    "step":  "Step #12",
    "layer":  "BossMind Performance Profiler",
    "scope":  "All 5 projects",
    "profiler_status":  "ACTIVE",
    "results":  [
                    {
                        "project":  "bossmind-resumora",
                        "path":  "D:\\BossMind\\bossmind-resumora",
                        "folder_exists":  true,
                        "file_count":  11801,
                        "folder_size_mb":  274.64,
                        "performance_status":  "MEASURED",
                        "checked_at":  "2026-05-03T01:34:28"
                    },
                    {
                        "project":  "bossmind-elegancyart",
                        "path":  "D:\\BossMind\\bossmind-elegancyart",
                        "folder_exists":  true,
                        "file_count":  7,
                        "folder_size_mb":  0,
                        "performance_status":  "MEASURED",
                        "checked_at":  "2026-05-03T01:34:28"
                    },
                    {
                        "project":  "bossmind-ai-video-generator",
                        "path":  "D:\\BossMind\\bossmind-ai-video-generator",
                        "folder_exists":  true,
                        "file_count":  5,
                        "folder_size_mb":  0,
                        "performance_status":  "MEASURED",
                        "checked_at":  "2026-05-03T01:34:28"
                    },
                    {
                        "project":  "bossmind-tiktok-ai",
                        "path":  "D:\\BossMind\\bossmind-tiktok-ai",
                        "folder_exists":  true,
                        "file_count":  6,
                        "folder_size_mb":  0,
                        "performance_status":  "MEASURED",
                        "checked_at":  "2026-05-03T01:34:28"
                    },
                    {
                        "project":  "bossmind-global-stock",
                        "path":  "D:\\BossMind\\bossmind-global-stock",
                        "folder_exists":  true,
                        "file_count":  5,
                        "folder_size_mb":  0,
                        "performance_status":  "MEASURED",
                        "checked_at":  "2026-05-03T01:34:28"
                    }
                ]
}'::jsonb
);
