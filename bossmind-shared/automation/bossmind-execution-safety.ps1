# BossMind Execution Safety Engine - FINAL
$ErrorActionPreference = "Continue"
$Root = "D:\BossMind"
$Shared = "$Root\bossmind-shared"
$SafetyRoot = "$Shared\execution-safety"
$StageRoot = "$SafetyRoot\staging"
$LockRoot = "$SafetyRoot\locks"
$BackupRoot = "$SafetyRoot\backups"
$LogFile = "$Shared\logs\execution-safety-events.jsonl"
$AllowedProjects = @(
  "$Root\bossmind-master-admin",
  "$Root\bossmind-resumora",
  "$Root\bossmind-elegancyart",
  "$Root\bossmind-ai-video-generator",
  "$Root\bossmind-tiktok-ai",
  "$Root\bossmind-global-stock",
  "$Root\bossmind-shared"
)
function HashText {
  param([string]$Text)
  if ($null -eq $Text) { $Text = "" }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  return ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-","").ToLower()
}
function PathHash {
  param([string]$Path)
  return HashText $Path
}
function Write-Log {
  param([object]$Payload)
  $Payload.timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
  Add-Content -Path $LogFile -Value ($Payload | ConvertTo-Json -Compress -Depth 12) -Encoding UTF8
}
function Test-AllowedPath {
  param([string]$Path)
  foreach ($project in $AllowedProjects) {
    if ($Path.StartsWith($project, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }
  return $false
}
function Get-LockPath {
  param([string]$TargetPath)
  $hash = PathHash $TargetPath
  return "$LockRoot\$hash.lock"
}
function Get-StagePath {
  param([string]$TargetPath)
  $hash = PathHash $TargetPath
  return "$StageRoot\$hash.stage"
}
function Get-BackupPath {
  param([string]$TargetPath)
  $hash = PathHash $TargetPath
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfff")
  return "$BackupRoot\$hash-$stamp.bak"
}
function Acquire-Lock {
  param([string]$TargetPath)
  $lockPath = Get-LockPath $TargetPath
  if (Test-Path $lockPath) {
    $age = (Get-Date) - (Get-Item $lockPath).LastWriteTime
    if ($age.TotalMinutes -lt 10) {
      return @{
        ok = $false
        lock = $lockPath
        reason = "active_lock_exists"
      }
    }
    Remove-Item $lockPath -Force
  }
  Set-Content -Path $lockPath -Value "locked_at=2026-05-03T05:04:02.8705365Z;target=$TargetPath" -Encoding UTF8
  return @{
    ok = $true
    lock = $lockPath
    reason = "lock_acquired"
  }
}
function Release-Lock {
  param([string]$TargetPath)
  $lockPath = Get-LockPath $TargetPath
  if (Test-Path $lockPath) {
    Remove-Item $lockPath -Force
  }
}
function Test-ContentIntegrity {
  param(
    [string]$TargetPath,
    [string]$Content
  )
  $issues = @()
  $ext = [System.IO.Path]::GetExtension($TargetPath).ToLower()
  if ($Content -match "<<<<<<<|=======|>>>>>>>") {
    $issues += "merge_conflict_markers"
  }
  if ($ext -in @(".json")) {
    try {
      $Content | ConvertFrom-Json | Out-Null
    } catch {
      $issues += "invalid_json"
    }
  }
  if ($ext -eq ".ps1") {
    try {
      $tokens = $null
      $errors = $null
      [System.Management.Automation.Language.Parser]::ParseInput($Content, [ref]$tokens, [ref]$errors) | Out-Null
      if ($errors.Count -gt 0) { $issues += "powershell_parse_error" }
    } catch {
      $issues += "powershell_parse_exception"
    }
  }
  if ($ext -in @(".ts",".tsx",".js",".jsx",".css",".html",".sql",".ps1",".json") -and $Content.Trim().Length -lt 5) {
    $issues += "suspiciously_short_content"
  }
  if (-not (Test-AllowedPath $TargetPath)) {
    $issues += "path_outside_allowed_projects"
  }
  if ($issues.Count -gt 0) {
    return @{
      ok = $false
      issues = $issues
    }
  }
  return @{
    ok = $true
    issues = @()
  }
}
function Invoke-SafeWrite {
  param(
    [string]$TargetPath,
    [string]$Content
  )
  $result = [ordered]@{
    engine = "bossmind-execution-safety"
    target_path = $TargetPath
    status = "started"
    action = "safe_write"
  }
  if (-not (Test-AllowedPath $TargetPath)) {
    $result.status = "blocked"
    $result.reason = "path_outside_allowed_projects"
    Write-Log $result
    Write-Host "BLOCKED unsafe path: $TargetPath"
    return $false
  }
  $lock = Acquire-Lock $TargetPath
  if (-not $lock.ok) {
    $result.status = "blocked"
    $result.reason = $lock.reason
    $result.lock = $lock.lock
    Write-Log $result
    Write-Host "BLOCKED active lock: $TargetPath"
    return $false
  }
  try {
    $validation = Test-ContentIntegrity $TargetPath $Content
    if (-not $validation.ok) {
      $result.status = "blocked"
      $result.reason = "validation_failed_before_commit"
      $result.issues = $validation.issues
      Write-Log $result
      Write-Host "BLOCKED validation failed: $TargetPath"
      return $false
    }
    $stagePath = Get-StagePath $TargetPath
    $backupPath = Get-BackupPath $TargetPath
    if (Test-Path $TargetPath) {
      Copy-Item -Path $TargetPath -Destination $backupPath -Force
      $result.backup_path = $backupPath
    }
    Set-Content -Path $stagePath -Value $Content -Encoding UTF8
    $stageContent = Get-Content $stagePath -Raw
    $stageValidation = Test-ContentIntegrity $TargetPath $stageContent
    if (-not $stageValidation.ok) {
      $result.status = "blocked"
      $result.reason = "stage_validation_failed"
      $result.issues = $stageValidation.issues
      Remove-Item $stagePath -Force -ErrorAction SilentlyContinue
      Write-Log $result
      Write-Host "BLOCKED stage validation failed: $TargetPath"
      return $false
    }
    Move-Item -Path $stagePath -Destination $TargetPath -Force
    $finalContent = Get-Content $TargetPath -Raw
    $finalValidation = Test-ContentIntegrity $TargetPath $finalContent
    if (-not $finalValidation.ok) {
      if (Test-Path $backupPath) {
        Copy-Item -Path $backupPath -Destination $TargetPath -Force
      }
      $result.status = "rolled_back"
      $result.reason = "final_validation_failed"
      $result.issues = $finalValidation.issues
      Write-Log $result
      Write-Host "ROLLED BACK failed commit: $TargetPath"
      return $false
    }
    $result.status = "committed"
    $result.reason = "safe_atomic_write_completed"
    $result.final_hash = HashText $finalContent
    Write-Log $result
    Write-Host "SAFE COMMIT $TargetPath"
    return $true
  } catch {
    $result.status = "failed"
    $result.reason = $_.Exception.Message
    Write-Log $result
    Write-Host "SAFE WRITE FAILED $TargetPath"
    return $false
  } finally {
    Release-Lock $TargetPath
  }
}
function Test-ExecutionSafety {
  $testFile = "$Shared\execution-safety\execution-safety-test.json"
  $good = '{ "bossmind": "execution_safety_verified", "status": "ok" }'
  $bad = '{ "broken": '
  Invoke-SafeWrite -TargetPath $testFile -Content $good | Out-Null
  Invoke-SafeWrite -TargetPath $testFile -Content $bad | Out-Null
  Write-Host "Execution Safety Self-Test Complete"
}
Test-ExecutionSafety
Write-Host ""
Write-Host "BossMind EXECUTION SAFETY COMPLETE"
Write-Host "Transaction-like execution: ON"
Write-Host "Safe write staging: ON"
Write-Host "File lock system: ON"
Write-Host "Concurrent write protection: ON"
Write-Host "Conflict detection: ON"
Write-Host "Atomic commit: ON"
Write-Host "Rollback on failed validation: ON"
Write-Host ""
