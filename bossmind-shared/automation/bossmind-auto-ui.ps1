param(
    [string]$Project = "resumora"
)

$ProjectPath = "D:\BossMind\bossmind-$Project"
$TargetFile = "$ProjectPath\app\client\page.tsx"

Write-Host "🚀 WRITING LATEST CLIENT UI..."

$UI = @"
export default function ClientPage() {
  return (
    <main style={{
      minHeight: "100vh",
      background: "linear-gradient(135deg, #0f172a, #1e3a8a)",
      color: "white",
      padding: "40px",
      fontFamily: "Arial"
    }}>
      <h1 style={{fontSize: "42px", fontWeight: "bold"}}>
        🚀 Resumora Luxury Client Interface (LIVE)
      </h1>

      <p style={{marginTop: "20px", fontSize: "18px"}}>
        This is the NEW automated BossMind UI version.
      </p>

      <div style={{marginTop: "40px"}}>
        <button style={{
          padding: "12px 24px",
          marginRight: "10px",
          background: "#facc15",
          color: "black",
          borderRadius: "8px"
        }}>
          Login
        </button>

        <button style={{
          padding: "12px 24px",
          background: "#2563eb",
          color: "white",
          borderRadius: "8px"
        }}>
          Register
        </button>
      </div>
    </main>
  );
}
"@

$UI | Set-Content -Path $TargetFile -Encoding UTF8

Write-Host "✅ UI WRITTEN"

cd $ProjectPath
git add -A
git commit -m "AUTO UI UPDATE"
git push

Write-Host "🚀 DEPLOY TRIGGERED"