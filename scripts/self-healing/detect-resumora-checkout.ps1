<#
.SYNOPSIS
  Detect Resumora checkout / one-time pricing / edit-allowance regressions (P1_HIGH).
#>
param(
  [string]$Project = "resumora",
  [string]$EvidenceDir = ""
)
$ErrorActionPreference = "Continue"
. "D:\BossMind\engineering\detectors\_common.ps1"
$paths = Get-BossMindPaths -Project resumora
if (-not $EvidenceDir) {
  $EvidenceDir = Join-Path $paths.DetectionsRoot (Get-Date -Format "yyyyMMdd-HHmmss")
  New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}
$outFile = Join-Path $EvidenceDir "detect-resumora-checkout.json"
$checks = [System.Collections.ArrayList]@()
$failures = [System.Collections.ArrayList]@()
$root = $paths.RepoRoot

function Fail([string]$Id, [string]$Msg) {
  Add-Failure $failures $Id $Msg "P1" "checkout" $Id
}

# site-copy /month
$siteCopy = Join-Path $root "lib\marketing\site-copy.js"
if (Test-Path $siteCopy) {
  $raw = Get-Content $siteCopy -Raw
  if ($raw -match 'pricingOneTimeNote:\s*"/month"' -or $raw -match 'pricingOneTimeNote:\s*"/mois"') {
    Fail "ui-month" "Pricing UI still shows /month or /mois"
  } else {
    Add-Check $checks "ui-month" "PASS" "No /month pricingOneTimeNote"
  }
  if ($raw -match 'Unlimited Resume Edits') {
    Fail "unlimited-copy" "Unlimited Resume Edits still present in site-copy"
  } else {
    Add-Check $checks "unlimited-copy" "PASS" "No Unlimited Resume Edits"
  }
  if ($raw -match '3 Free Resume Edits' -and $raw -match 'id:\s*"professional"') {
    # Balanced must be 2, not 3 on professional id features
  }
}

# plan-policy matrix
$policy = Join-Path $root "lib\client\plan-policy.js"
if (Test-Path $policy) {
  $p = Get-Content $policy -Raw
  $ok = ($p -match 'basic:\s*1') -and ($p -match 'professional:\s*2') -and ($p -match 'elite:\s*3') -and ($p -match 'essential_advanced:\s*0')
  if ($ok) { Add-Check $checks "edit-matrix" "PASS" "Edit matrix 1/2/3/0" }
  else { Fail "edit-matrix" "Edit matrix not 1/2/3/0 in plan-policy.js" }
}

# checkout mode payment + no client price fallback
$checkout = Join-Path $root "pages\api\checkout.js"
if (Test-Path $checkout) {
  $c = Get-Content $checkout -Raw
  if ($c -match 'mode:\s*"payment"') { Add-Check $checks "checkout-mode" "PASS" "mode payment" }
  else { Fail "checkout-mode" "checkout missing mode payment" }
  if ($c -match 'mode:\s*"subscription"') { Fail "checkout-sub" "subscription mode present" }
  if ($c -match 'CLIENT_PRICE_ID_REJECTED') { Add-Check $checks "no-client-price" "PASS" "Client Price ID rejected" }
  else { Fail "no-client-price" "Client Price ID rejection missing" }
  if ($c -match 'STRIPE_AMOUNT_MISMATCH') { Add-Check $checks "amount-guard" "PASS" "Amount mismatch guard present" }
  else { Fail "amount-guard" "Stripe amount mismatch guard missing" }
}

# redirect host guard
$urls = Join-Path $root "lib\marketing\stripe-checkout-urls.js"
if (Test-Path $urls) {
  $u = Get-Content $urls -Raw
  if ($u -match 'onrender\.com' -and $u -match 'FORBIDDEN') { Add-Check $checks "render-guard" "PASS" "Render host rejected" }
  else { Fail "render-guard" "Render rejection missing in checkout URLs" }
  if ($u -match '/pricing') { Add-Check $checks "cancel-pricing" "PASS" "Cancel uses /pricing" }
  else { Fail "cancel-pricing" "Cancel URL not /pricing" }
}

# canonical registry
$reg = Join-Path $root "lib\client\canonical-plan-registry.js"
if (Test-Path $reg) {
  $r = Get-Content $reg -Raw
  if ($r -match 'amountCents:\s*7900' -and $r -notmatch 'amountCents:\s*9900') {
    Add-Check $checks "elite-79" "PASS" "Professional canonical 7900 not 9900"
  } else { Fail "elite-79" "Professional not locked at 7900 cents" }
  if ($r -match 'isTutorialOnly:\s*true') { Add-Check $checks "advanced-tutorial" "PASS" "Advanced tutorial-only" }
  else { Fail "advanced-tutorial" "Advanced tutorial flag missing" }
}

$status = if ($failures.Count -gt 0) { "FAIL" } else { "PASS" }
Write-DetectorResult -Detector "detect-resumora-checkout" -Project $Project -Status $status -Checks $checks -Failures $failures -EvidencePath $outFile
if ($global:BossMindDetectorExitCode -eq 1) { exit 1 } else { exit 0 }
