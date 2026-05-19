param(
  [string]$Manifest = "D:\BossMind\bossmind-shared\automation\anti-leak-manifest.json"
)

Write-Output "ANTI_LEAK_FAST_SCAN_START"

$left = "<" * 7
$mid = "=" * 7
$right = ">" * 7

$data = Get-Content $Manifest | ConvertFrom-Json
$violations = @()

foreach ($pattern in $data.scan_targets) {
  $files = Get-ChildItem -Path $pattern -Recurse -File -ErrorAction SilentlyContinue

  foreach ($file in $files) {
    try {
      $content = [System.IO.File]::ReadAllText($file.FullName)
    } catch {
      continue
    }

    if ($content.Contains($left) -or $content.Contains($mid) -or $content.Contains($right)) {
      $violations += $file.FullName
    }
  }
}

if ($violations.Count -gt 0) {
  Write-Output "ANTI_LEAK_BLOCKED"
  $violations
  exit 1
}

Write-Output "ANTI_LEAK_CLEAN"
exit 0
