$ErrorActionPreference = "Stop"

$root = "D:\BossMind"
$shared = "$root\bossmind-shared"
$automation = "$shared\automation"
$logs = "$shared\logs"
$apiLog = "$logs\bossmind-local-api-log.json"

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:5055/")
$listener.Start()

Write-Host "✅ BossMind Local PowerShell API ACTIVE"
Write-Host "✅ Listening: http://localhost:5055/"
Write-Host "✅ Routes:"
Write-Host "   /health"
Write-Host "   /run-validation"
Write-Host "   /final-proof"
Write-Host "   /performance"
Write-Host "   /risk"

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response
    $path = $request.Url.AbsolutePath

    $status = "OK"
    $message = ""
    $output = ""

    try {
        if ($path -eq "/health") {
            $script = "$automation\bossmind-unified-health-monitor.ps1"
            $output = powershell -ExecutionPolicy Bypass -File $script 2>&1 | Out-String
            $message = "Health monitor executed"
        }
        elseif ($path -eq "/run-validation") {
            $script = "$automation\bossmind-auto-validation-loop.ps1"
            $output = powershell -ExecutionPolicy Bypass -File $script 2>&1 | Out-String
            $message = "Validation loop executed"
        }
        elseif ($path -eq "/final-proof") {
            $script = "$automation\bossmind-validation-final-proof-lock.ps1"
            $output = powershell -ExecutionPolicy Bypass -File $script 2>&1 | Out-String
            $message = "Final proof lock executed"
        }
        elseif ($path -eq "/performance") {
            $script = "$automation\bossmind-performance-profiler.ps1"
            $output = powershell -ExecutionPolicy Bypass -File $script 2>&1 | Out-String
            $message = "Performance profiler executed"
        }
        elseif ($path -eq "/risk") {
            $script = "$automation\bossmind-predictive-risk-engine.ps1"
            $output = powershell -ExecutionPolicy Bypass -File $script 2>&1 | Out-String
            $message = "Predictive risk engine executed"
        }
        else {
            $status = "ERROR"
            $message = "Unknown route"
        }
    }
    catch {
        $status = "ERROR"
        $message = $_.Exception.Message
        $output = $_ | Out-String
    }

    $result = [ordered]@{
        timestamp = (Get-Date).ToString("s")
        route = $path
        status = $status
        message = $message
        output = $output
    }

    $result | ConvertTo-Json -Depth 20 | Set-Content -Path $apiLog -Encoding UTF8

    $json = $result | ConvertTo-Json -Depth 20
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)

    $response.ContentType = "application/json"
    $response.StatusCode = 200
    $response.OutputStream.Write($buffer, 0, $buffer.Length)
    $response.Close()
}
