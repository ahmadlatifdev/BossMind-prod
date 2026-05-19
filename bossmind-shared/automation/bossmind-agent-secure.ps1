$ErrorActionPreference = "Stop"

$SECRET = "BOSSMIND_SECURE_KEY_2026"

$allowed = @(
    "health",
    "validation",
    "risk",
    "performance"
)

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://+:7070/")
$listener.Start()

Write-Host "✅ BossMind SECURE AGENT ACTIVE (PORT 7070)"
Write-Host "🔒 Auth + Whitelist ENABLED"

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response

    $body = New-Object IO.StreamReader($req.InputStream).ReadToEnd()

    try {
        $data = $body | ConvertFrom-Json
        $action = $data.action
        $key = $data.key
    } catch {
        $action = ""
        $key = ""
    }

    # AUTH CHECK
    if ($key -ne $SECRET) {
        $out = "ACCESS DENIED"
    }
    elseif ($allowed -notcontains $action) {
        $out = "BLOCKED ACTION"
    }
    else {
        switch ($action) {
            "health" {
                $out = powershell -ExecutionPolicy Bypass -File "D:\BossMind\bossmind-shared\automation\bossmind-unified-health-monitor.ps1"
            }
            "validation" {
                $out = powershell -ExecutionPolicy Bypass -File "D:\BossMind\bossmind-shared\automation\bossmind-auto-validation-loop.ps1"
            }
            "risk" {
                $out = powershell -ExecutionPolicy Bypass -File "D:\BossMind\bossmind-shared\automation\bossmind-predictive-risk-engine.ps1"
            }
            "performance" {
                $out = powershell -ExecutionPolicy Bypass -File "D:\BossMind\bossmind-shared\automation\bossmind-performance-profiler.ps1"
            }
        }
    }

    $json = @{
        status = "OK"
        action = $action
        result = $out
    } | ConvertTo-Json -Depth 10

    $buf = [Text.Encoding]::UTF8.GetBytes($json)
    $res.OutputStream.Write($buf,0,$buf.Length)
    $res.Close()
}
