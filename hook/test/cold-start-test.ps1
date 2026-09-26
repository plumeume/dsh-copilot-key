# Verifies the cold-start branch of launch-dsh.ps1 (port closed -> start server -> browser opens ONCE)
# without touching a real DeepSeek Harness instance. A stub "dsh" on PATH mirrors "dsh web": it
# opens the browser itself. The test fails if the browser is opened twice (the double-tab bug).
$ErrorActionPreference = 'Stop'
$root    = Split-Path $PSScriptRoot -Parent
$port    = 3099
$url     = "http://127.0.0.1:$port"
$fakeLog = Join-Path $PSScriptRoot 'fake-server.log'
Remove-Item $fakeLog -ErrorAction SilentlyContinue
Remove-Item (Join-Path $root 'launcher.log') -ErrorAction SilentlyContinue

$env:PATH = "$PSScriptRoot;$env:PATH"
$env:DSH_LAUNCH_PORT = "$port"
$env:DSH_LAUNCH_URL  = $url
# skip the desktop-app branch of launch-dsh.ps1 so this test can still reach the web path
$env:DSH_LAUNCH_FORCE_WEB = '1'

$proc = Start-Process -FilePath 'powershell' -PassThru -WindowStyle Minimized -ArgumentList @(
    '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'launch-dsh.ps1'))

function Get-Opens {
    if (-not (Test-Path $fakeLog)) { return 0 }
    return @(Get-Content $fakeLog | Where-Object { $_ -match 'HTTP request: GET / ' }).Count
}

# wait for the first browser hit, then keep watching for a duplicate
$first = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 500
    if ((Get-Opens) -ge 1) { $first = $true; break }
}
if ($first) { Start-Sleep -Seconds 6 }
$opens = Get-Opens

Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
    Where-Object { $_.CommandLine -like '*fake-server.js*' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host '--- launcher.log ---' -ForegroundColor Cyan
Get-Content (Join-Path $root 'launcher.log') -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" }
Write-Host '--- stub server log ---' -ForegroundColor Cyan
Get-Content $fakeLog -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" }
Write-Host ''

$fail = 0
if ($first) { Write-Host 'PASS  launcher started the server' -ForegroundColor Green }
else { Write-Host 'FAIL  server never came up' -ForegroundColor Red; $fail++ }

if ($opens -eq 1) { Write-Host 'PASS  browser opened exactly once (no double tab)' -ForegroundColor Green }
else { Write-Host "FAIL  browser opened $opens times (expected 1)" -ForegroundColor Red; $fail++ }

Write-Host ''
if ($fail -eq 0) { Write-Host 'COLD-START TEST PASSED' -ForegroundColor Green; exit 0 }
Write-Host 'COLD-START TEST FAILED' -ForegroundColor Red; exit $fail
