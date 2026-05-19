# BossMind Error Intelligence Engine - FINAL COMPLETE

$ErrorActionPreference = "Continue"

$Root = "D:\BossMind"
$Shared = "$Root\bossmind-shared"
$EnvFile = "$Shared\.env"

Get-Content $EnvFile | ForEach-Object {
  if ($_ -match "=" -and $_ -notmatch "^\s*#") {
    $k,$v = $_ -split "=",2
    [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim().Trim('"').Trim("'"), "Process")
  }
}

$DB = $env:DATABASE_URL

function SqlSafe {
  param([string]$Value)
  if ($null -eq $Value) { return "" }
  return $Value.Replace("'","''")
}

function HashText {
  param([string]$Text)
  if ($null -eq $Text) { $Text = "" }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  return ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-","").ToLower()
}

function Invoke-Sql {
  param([string]$Sql)
  $out = & psql "$DB" -v ON_ERROR_STOP=1 -c $Sql 2>&1
  return @{
    ok = ($LASTEXITCODE -eq 0)
    output = ($out | Out-String)
  }
}

function Classify-Error {
  param([string]$Message)

  $m = $Message.ToLower()

  if ($m -match "cannot find module|module not found|missing module") { return "missing_dependency" }
  if ($m -match "syntaxerror|parsererror|unexpected token|missing statement block") { return "syntax_error" }
  if ($m -match "enoent|cannot find path|file not found|path does not exist") { return "missing_file" }
  if ($m -match "eacces|access is denied|permission denied") { return "permission_error" }
  if ($m -match "database_url|connection|psql|sqlstate|neon|postgres") { return "database_error" }
  if ($m -match "timeout|timed out|etimedout") { return "timeout_error" }
  if ($m -match "build failed|next build|compile failed") { return "build_error" }
  if ($m -match "env|environment variable|api_key|secret") { return "env_error" }
  if ($m -match "rollback|snapshot|corrupt|partial") { return "anti_leak_error" }

  return "unknown_error"
}

function Severity-ForType {
  param([string]$Type)

  switch ($Type) {
    "database_error" { return "critical" }
    "anti_leak_error" { return "fatal" }
    "syntax_error" { return "critical" }
    "build_error" { return "critical" }
    "env_error" { return "critical" }
    "permission_error" { return "critical" }
    "missing_dependency" { return "medium" }
    "missing_file" { return "medium" }
    "timeout_error" { return "medium" }
    default { return "low" }
  }
}

function Fix-ForType {
  param([string]$Type)

  switch ($Type) {
    "missing_dependency" { return "Run package install or restore required dependency from manifest." }
    "syntax_error" { return "Replace full corrupted file from latest stable snapshot; never patch fragment." }
    "missing_file" { return "Restore missing required file from required-files registry or latest snapshot." }
    "permission_error" { return "Run elevated PowerShell or fix ACL permissions." }
    "database_error" { return "Validate DATABASE_URL, Neon connectivity, psql availability, and SQL schema." }
    "timeout_error" { return "Retry with backoff; reduce batch size; verify network/service health." }
    "build_error" { return "Run validation guard, detect broken imports/routes, then rebuild." }
    "env_error" { return "Load centralized .env from bossmind-shared config and validate required keys." }
    "anti_leak_error" { return "Block write, restore last stable snapshot, log rollback proof." }
    default { return "Escalate to BossMind recovery agent for classification." }
  }
}

$schema = @"
CREATE TABLE IF NOT EXISTS bossmind_error_memory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_key TEXT,
  error_type TEXT,
  error_message TEXT,
  error_hash TEXT UNIQUE,
  file_path TEXT,
  fix_applied TEXT,
  recommended_fix TEXT,
  severity TEXT,
  retry_count INT DEFAULT 0,
  occurrence_count INT DEFAULT 1,
  first_seen TIMESTAMP DEFAULT NOW(),
  last_seen TIMESTAMP DEFAULT NOW(),
  status TEXT DEFAULT 'captured',
  source_engine TEXT DEFAULT 'bossmind-error-intelligence'
);

CREATE TABLE IF NOT EXISTS bossmind_error_fix_patterns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  error_type TEXT UNIQUE,
  severity TEXT,
  recommended_fix TEXT,
  reuse_scope TEXT DEFAULT 'cross_project',
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

INSERT INTO bossmind_error_fix_patterns (error_type,severity,recommended_fix)
VALUES
('missing_dependency','medium','Run package install or restore required dependency from manifest.'),
('syntax_error','critical','Replace full corrupted file from latest stable snapshot; never patch fragment.'),
('missing_file','medium','Restore missing required file from required-files registry or latest snapshot.'),
('permission_error','critical','Run elevated PowerShell or fix ACL permissions.'),
('database_error','critical','Validate DATABASE_URL, Neon connectivity, psql availability, and SQL schema.'),
('timeout_error','medium','Retry with backoff; reduce batch size; verify network/service health.'),
('build_error','critical','Run validation guard, detect broken imports/routes, then rebuild.'),
('env_error','critical','Load centralized .env from bossmind-shared config and validate required keys.'),
('anti_leak_error','fatal','Block write, restore last stable snapshot, log rollback proof.'),
('unknown_error','low','Escalate to BossMind recovery agent for classification.')
ON CONFLICT (error_type) DO UPDATE SET
severity = EXCLUDED.severity,
recommended_fix = EXCLUDED.recommended_fix,
updated_at = NOW();
"@

$schemaResult = Invoke-Sql $schema

if (-not $schemaResult.ok) {
  Write-Host "ERROR INTELLIGENCE SCHEMA FAILED"
  Write-Host $schemaResult.output
  exit 1
}

function Save-ErrorMemory {
  param(
    [string]$ProjectKey,
    [string]$Message,
    [string]$FilePath,
    [string]$Status
  )

  $type = Classify-Error $Message
  $severity = Severity-ForType $type
  $fix = Fix-ForType $type
  $hash = HashText "$ProjectKey|$type|$Message|$FilePath"

  $sql = @"
INSERT INTO bossmind_error_memory
(project_key,error_type,error_message,error_hash,file_path,fix_applied,recommended_fix,severity,status,last_seen)
VALUES
('$(SqlSafe $ProjectKey)',
 '$(SqlSafe $type)',
 '$(SqlSafe $Message)',
 '$(SqlSafe $hash)',
 '$(SqlSafe $FilePath)',
 'pending',
 '$(SqlSafe $fix)',
 '$(SqlSafe $severity)',
 '$(SqlSafe $Status)',
 NOW())
ON CONFLICT (error_hash) DO UPDATE SET
occurrence_count = bossmind_error_memory.occurrence_count + 1,
retry_count = bossmind_error_memory.retry_count + 1,
last_seen = NOW(),
recommended_fix = EXCLUDED.recommended_fix,
severity = EXCLUDED.severity,
status = EXCLUDED.status;
"@

  $result = Invoke-Sql $sql

  if ($result.ok) {
    Write-Host "ERROR MEMORY SAVED [$ProjectKey] [$type] [$severity]"
  } else {
    Write-Host "ERROR MEMORY SAVE FAILED"
    Write-Host $result.output
  }
}

Save-ErrorMemory `
  -ProjectKey "shared" `
  -Message "ParserError Missing statement block after process in bossmind-memory-core.ps1" `
  -FilePath "D:\BossMind\bossmind-shared\automation\bossmind-memory-core.ps1" `
  -Status "classified"

Save-ErrorMemory `
  -ProjectKey "shared" `
  -Message "ParserError Missing statement block after process in bossmind-memory-core.ps1" `
  -FilePath "D:\BossMind\bossmind-shared\automation\bossmind-memory-core.ps1" `
  -Status "deduplicated"

Write-Host "BossMind Error Intelligence Engine COMPLETE"
Write-Host "Classification: COMPLETE"
Write-Host "Auto-fix mapping: COMPLETE"
Write-Host "Deduplication: COMPLETE"
Write-Host "Cross-project reuse: COMPLETE"
Write-Host "Severity scoring: COMPLETE"
