# Self-test for the Copilot-key remap.
# It synthesises exactly what the hardware key emits (LeftWin + LeftShift + F23),
# then checks that the watcher fired and that the Start menu did NOT pop up.
$ErrorActionPreference = 'Stop'
$dir = $PSScriptRoot
$exe = Join-Path $dir 'DshCopilotKey.exe'
$log = Join-Path $dir 'watcher.log'
$cfg = Join-Path $dir 'config.ini'

Add-Type -Namespace Native -Name Win -MemberDefinition @"
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
"@

function Get-Fg {
    $h = [Native.Win]::GetForegroundWindow()
    $c = New-Object System.Text.StringBuilder 256
    $t = New-Object System.Text.StringBuilder 256
    [void][Native.Win]::GetClassName($h, $c, 256)
    [void][Native.Win]::GetWindowText($h, $t, 256)
    [pscustomobject]@{ Class = $c.ToString(); Title = $t.ToString() }
}

function Set-DryRun([string]$value) {
    $lines = @(Get-Content $cfg)
    $seen = $false
    $out = foreach ($l in $lines) {
        if ($l -match '^\s*dryrun\s*=') { $seen = $true; "dryrun = $value" } else { $l }
    }
    if (-not $seen) { $out = @($out) + "dryrun = $value" }
    Set-Content -Path $cfg -Value $out -Encoding UTF8
}

function Invoke-CopilotKey {
    Start-Process -FilePath $exe -ArgumentList 'simulate-raw' -Wait
}

$fail = 0

Write-Host '--- phase 1: hook behaviour (dry run, nothing is launched) ---' -ForegroundColor Cyan
Set-DryRun '1'
Start-Sleep -Milliseconds 300
$before = @(Get-Content $log -ErrorAction SilentlyContinue).Count
$fgBefore = Get-Fg
Invoke-CopilotKey
Start-Sleep -Milliseconds 600
$fgAfter = Get-Fg
$new = @(Get-Content $log | Select-Object -Skip $before)

if ($new -match 'Copilot key detected') { Write-Host 'PASS  watcher detected the key' -ForegroundColor Green }
else { Write-Host 'FAIL  watcher did not detect the key' -ForegroundColor Red; $fail++ }

if ($new -match 'dry-run') { Write-Host 'PASS  dry run honoured' -ForegroundColor Green }
else { Write-Host 'FAIL  dry run not honoured' -ForegroundColor Red; $fail++ }

$startOpen = ($fgAfter.Class -eq 'Windows.UI.Core.CoreWindow' -and $fgAfter.Title -eq 'Start')
if ($startOpen) { Write-Host "FAIL  Start menu opened (foreground: $($fgAfter.Class) / $($fgAfter.Title))" -ForegroundColor Red; $fail++ }
else { Write-Host "PASS  Start menu stayed closed (foreground: $($fgAfter.Class) / $($fgAfter.Title))" -ForegroundColor Green }

Write-Host ''
Write-Host '--- phase 2: real launch path ---' -ForegroundColor Cyan
Set-DryRun '0'
Start-Sleep -Milliseconds 300
$before = @(Get-Content $log -ErrorAction SilentlyContinue).Count
Invoke-CopilotKey
Start-Sleep -Seconds 3
$new = @(Get-Content $log | Select-Object -Skip $before)

if ($new -match 'already listening|starting launcher|starting:') { Write-Host 'PASS  launch path executed' -ForegroundColor Green }
else { Write-Host 'FAIL  launch path did not execute' -ForegroundColor Red; $fail++ }

Write-Host ''
Write-Host '--- watcher log (new lines) ---' -ForegroundColor Cyan
$new | ForEach-Object { Write-Host "  $_" }

Write-Host ''
if ($fail -eq 0) { Write-Host 'SELF-TEST PASSED' -ForegroundColor Green } else { Write-Host "SELF-TEST FAILED ($fail checks)" -ForegroundColor Red }
exit $fail
