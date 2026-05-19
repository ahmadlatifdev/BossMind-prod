$ErrorActionPreference = "Stop"

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:6060/")
$listener.Start()

Write-Host "✅ BossMind n8n Bridge ACTIVE on http://localhost:6060/"

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $req = $context.Request
    $res = $context.Response

    $body = New-Object IO.StreamReader($req.InputStream).ReadToEnd()

    $action = "health"
    try {
        if ($body) {
            $json = $body | ConvertFrom-Json
            $action = $json.action
        }
    } catch {}

    switch ($action) {
        "health" {
            $out = Invoke-RestMethod "http://localhost:5055/health"
        }
        "validation" {
            $out = Invoke-RestMethod "http://localhost:5055/run-validation"
        }
        "risk" {
            $out = Invoke-RestMethod "http://localhost:5055/risk"
        }
        default {
            $out = "Unknown action"
        }
    }

    $buffer = [Text.Encoding]::UTF8.GetBytes(($out | ConvertTo-Json -Depth 20))
    $res.OutputStream.Write($buffer,0,$buffer.Length)
    $res.Close()
}
