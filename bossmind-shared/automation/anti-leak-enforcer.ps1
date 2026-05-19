param(
  [string]$Root = "D:\BossMind"
)

Write-Output "ANTI_LEAK_SCAN_START"

$excludeDirs = @("\node_modules\", "\.next\", "\.git\", "\dist\", "\build\", "\coverage\")

$files = Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue |
  Where-Object {
    $path = $_.FullName
    $ext = $_.Extension.ToLower()
    ($ext -in ".js",".ts",".tsx",".json",".env",".ps1") -and
    -not ($excludeDirs | Where-Object { $path -like "*$_*" })
  }

$violations = @()

foreach ($file in $files) {
  try {
    $content = [System.IO.File]::ReadAllText($file.FullName)
  } catch {
    continue
  }

  if (
  ) {
    $violations += $file.FullName
  }
}

if ($violations.Count -gt 0) {
  Write-Output "ANTI_LEAK_BLOCKED"
  $violations
  exit 1
}

Write-Output "ANTI_LEAK_CLEAN"
exit 0
