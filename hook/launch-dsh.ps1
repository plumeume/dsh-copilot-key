#Requires -Version 5
# Launched by DshCopilotKey.exe when the Copilot key is pressed and no DSH web server is running yet.
#
# NOTE: "dsh web" already opens the Web UI in the default browser by itself. On a cold start this
# script therefore only starts the server - opening the browser here as well would give two tabs.
# The already-running path below (and the watcher) does open the browser, because then nothing else will.
$ErrorActionPreference = 'Continue'
$port = 3080
$url  = "http://127.0.0.1:$port"
if ($env:DSH_LAUNCH_PORT) { $port = [int]$env:DSH_LAUNCH_PORT }
if ($env:DSH_LAUNCH_URL)  { $url  = $env:DSH_LAUNCH_URL }
$log  = Join-Path $PSScriptRoot 'launcher.log'

function Write-Log([string]$m) {
    Add-Content -Path $log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $m) -Encoding UTF8
}

function Test-DshPort([int]$p) {
    try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1', $p); $c.Close(); return $true } catch { return $false }
}

# Integrity preflight. Windows gives a child process IL = min(parent IL, image file IL), so a
# Low-labelled DshCopilotKey.exe drags this whole chain down to Low. Low integrity is subject to
# no-write-up and therefore cannot write %USERPROFILE%\.dsh (Medium) -- that is exactly the
# "Error: EPERM ... open '...\profiles\web\cordis.yml'" trace from prepareProfile.
# S-1-16-4096 = Low Mandatory Level, S-1-16-8192 = Medium.
if ((whoami /groups) 2>$null | Select-String -Quiet 'S-1-16-4096') {
    # Add-Content directly: Write-Log may itself be unable to write launcher.log while the tree
    # is still Medium-labelled but this process is Low.
    Add-Content -Path $log -Encoding UTF8 -ErrorAction SilentlyContinue -Value ("{0} FATAL: launched at Low integrity level -> dsh cannot write its profile" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'))
    Write-Host 'FATAL: this launch chain runs at Low integrity (S-1-16-4096), so dsh cannot write its profile and dies with EPERM.' -ForegroundColor Red
    Write-Host 'Fix: icacls <hook dir> /setintegritylevel "(OI)(CI)Medium"' -ForegroundColor Yellow
    Write-Host 'Then restart the watcher (log off/on, or Stop-Process DshCopilotKey then Start-ScheduledTask DshCopilotKey) and press the key again.' -ForegroundColor Yellow
    exit 1
}

Write-Host '================================================' -ForegroundColor Cyan
Write-Host '  DeepSeek Harness   (launched from Copilot key)' -ForegroundColor Cyan
Write-Host '================================================' -ForegroundColor Cyan

# ---- Desktop app first (2026-09-25) -------------------------------------------------------
# The global/npx dsh CLI was removed on 2026-09-25 when its plugins moved into the desktop
# app's own profile (~/.dsh/profiles/desktop). Without this branch the Copilot key would fall
# through to "npx -y @deepseek-ai/dsh@alpha web" and silently re-download a second harness.
# Behaviour now: focus the running desktop app, else start it. The web-server path below stays
# as a fallback for the case where the desktop install is missing.
$desktopExe = Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\DeepSeek Harness.exe'
$desktopMain = Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle } | Select-Object -First 1
if ($desktopMain) {
    Write-Log "desktop app already running (pid $($desktopMain.Id)) -> focusing its window"
    Write-Host 'DeepSeek Harness desktop app is already running - focusing it' -ForegroundColor Green
    try { (New-Object -ComObject WScript.Shell).AppActivate([int]$desktopMain.Id) | Out-Null } catch { }
    exit 0
}
if (Test-Path $desktopExe) {
    Write-Log "starting desktop app: $desktopExe"
    Write-Host 'starting DeepSeek Harness (desktop app) ...' -ForegroundColor Yellow
    Start-Process $desktopExe
    exit 0
}
# ---- Fallback: legacy web server path ------------------------------------------------------
if (Test-DshPort $port) {
    Write-Log "port $port already listening -> opening $url"
    Write-Host "DeepSeek Harness is already running - opening $url" -ForegroundColor Green
    Start-Process $url
    exit 0
}

# Best available local npx-cached build (highest version; prerelease suffix ignored).
$cached = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'npm-cache\_npx') -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $bin = Join-Path $_.FullName 'node_modules\@deepseek-ai\dsh\lib\bin.js'
    $pkg = Join-Path $_.FullName 'node_modules\@deepseek-ai\dsh\package.json'
    if ((Test-Path $bin) -and (Test-Path $pkg)) {
        $v = [version]'0.0.0'
        try { $v = [version](((Get-Content $pkg -Raw | ConvertFrom-Json).version -split '-')[0]) } catch { }
        [pscustomobject]@{ Path = $bin; Version = $v }
    }
} | Sort-Object Version -Descending | Select-Object -First 1

$dsh = Get-Command dsh -ErrorAction SilentlyContinue
if ($dsh) {
    Write-Log "starting: dsh web  ($($dsh.Source))"
    Write-Host 'starting dsh web ...' -ForegroundColor Yellow
    & $dsh.Source web
} elseif ($cached) {
    Write-Log "starting cached build: $($cached.Path)"
    Write-Host 'starting dsh web (local cached build) ...' -ForegroundColor Yellow
    & node $cached.Path web
} else {
    Write-Log 'starting: npx -y @deepseek-ai/dsh@alpha web'
    Write-Host 'starting dsh web (via npx) ...' -ForegroundColor Yellow
    & npx -y '@deepseek-ai/dsh@alpha' web
}

$code = $LASTEXITCODE
if ($code -ne 0) {
    Write-Log "dsh web exited with $code"
    if (Test-DshPort $port) {
        Write-Log "server still listening -> opening $url"
        Start-Process $url
    }
}
exit $code
