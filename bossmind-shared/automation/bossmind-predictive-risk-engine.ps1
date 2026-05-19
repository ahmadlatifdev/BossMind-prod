$ErrorActionPreference = "Stop"

$root = "D:\BossMind"
$shared = "$root\bossmind-shared"
$logs = "$shared\logs"
$riskLog = "$logs\bossmind-predictive-risk-engine-log.json"

$projects = @(
    "bossmind-resumora",
    "bossmind-elegancyart",
    "bossmind-ai-video-generator",
    "bossmind-tiktok-ai",
    "bossmind-global-stock"
)

$results = @()

foreach ($project in $projects) {
    $path = Join-Path $root $project
    $missing = @()
    $riskScore = 0

    $required = @(
        "automation",
        "required-files.json",
        "route-map.json",
        "deploy-config.json",
        "error-patterns.json"
    )

    foreach ($item in $required) {
        if (!(Test-Path (Join-Path $path $item))) {
            $missing += $item
            $riskScore += 20
        }
    }

    $riskLevel = if ($riskScore -eq 0) { "LOW" } elseif ($riskScore -le 40) { "MEDIUM" } else { "HIGH" }

    $results += [ordered]@{
        project = $project
        path = $path
        missing_items = $missing
        risk_score = $riskScore
        risk_level = $riskLevel
        predicted_status = if ($riskLevel -eq "LOW") { "SAFE_TO_CONTINUE" } else { "REQUIRES_FIX" }
        checked_at = (Get-Date).ToString("s")
    }
}

$overallRisk = if (($results | Where-Object { $_.risk_level -eq "HIGH" }).Count -gt 0) {
    "HIGH"
} elseif (($results | Where-Object { $_.risk_level -eq "MEDIUM" }).Count -gt 0) {
    "MEDIUM"
} else {
    "LOW"
}

$report = [ordered]@{
    timestamp = (Get-Date).ToString("s")
    step = "Step #13"
    layer = "BossMind Predictive Risk Engine"
    scope = "All 5 projects"
    predictive_engine = "ACTIVE"
    overall_risk = $overallRisk
    results = $results
}

$report | ConvertTo-Json -Depth 30 | Set-Content -Path $riskLog -Encoding UTF8

$eventJson = ($report | ConvertTo-Json -Depth 30).Replace("'", "''")

$sql = @"
CREATE TABLE IF NOT EXISTS bossmind_predictive_risk_events (
    id BIGSERIAL PRIMARY KEY,
    project_scope TEXT NOT NULL,
    event_type TEXT NOT NULL,
    risk_level TEXT NOT NULL,
    event_data JSONB NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO bossmind_predictive_risk_events (
    project_scope,
    event_type,
    risk_level,
    event_data
)
VALUES (
    'all_projects',
    'predictive_risk_engine',
    '$overallRisk',
    '$eventJson'::jsonb
);
"@

$sqlFile = Join-Path $logs "bossmind-predictive-risk-engine.sql"
Set-Content -Path $sqlFile -Value $sql -Encoding UTF8

psql "$env:DATABASE_URL" -v ON_ERROR_STOP=1 -f $sqlFile | Out-Host

Write-Host "✅ Step #13 COMPLETE"
Write-Host "✅ Predictive Risk Engine ACTIVE"
Write-Host "✅ Overall risk: $overallRisk"
Write-Host "✅ Neon predictive risk event saved"
Write-Host "✅ Log saved: $riskLog"
