param(
  [string]$Project = "resumora"
)

$Source = "D:\BossMind\bossmind-resumora\app\page.tsx"
$Approved = "D:\BossMind\bossmind-shared\locked-snapshots\resumora\approved-ui-source.tsx"
$Checksum = "D:\BossMind\bossmind-shared\locked-snapshots\resumora\app-page.sha256"
$SnapshotLog = "D:\BossMind\bossmind-shared\optimization\snapshot-log.json"

Copy-Item $Source $Approved -Force

$sha = [System.Security.Cryptography.SHA256]::Create()
$stream = [System.IO.File]::OpenRead($Approved)
$hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "")
$stream.Dispose()
$sha.Dispose()

Set-Content $Checksum $hash -Encoding UTF8

$Log = @{
  timestamp = (Get-Date).ToString("s")
  project = $Project
  snapshot = "LOCKED"
  checksum = $hash
}

$Log | ConvertTo-Json -Depth 3 | Set-Content $SnapshotLog -Encoding UTF8
$Log | ConvertTo-Json -Depth 3
