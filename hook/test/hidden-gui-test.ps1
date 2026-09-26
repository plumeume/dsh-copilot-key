# Regression test for the other half of the silent-launch change: a GUI app started from the
# *invisible* chain must still get a visible window (that is how the key cold-starts the desktop app).
# It mirrors DshCopilotKey.StartHidden exactly - cmd -> powershell started with CreateNoWindow -
# and then launches a GUI program from inside that chain.
#
#   powershell -ExecutionPolicy Bypass -File test\hidden-gui-test.ps1
#
# PASS = a window for the launched app showed up. A temporary stub script is written to %TEMP%
# and removed again, so nothing is added to the working tree.
param([string]$App = 'notepad.exe', [int]$TimeoutSeconds = 12)

$stub = Join-Path $env:TEMP 'dsh-copilot-key-gui-stub.cmd'
Set-Content -LiteralPath $stub -Encoding ASCII -Value @(
    '@echo off',
    "powershell -NoProfile -Command `"Start-Process $App`""
)

$procName = [IO.Path]::GetFileNameWithoutExtension($App)
$before = @(Get-Process $procName -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })

# the same ProcessStartInfo the watcher uses
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = 'cmd.exe'
$psi.Arguments = '/c ""' + $stub + '""'
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
$psi.EnvironmentVariables['DSH_COPILOT_HIDDEN'] = '1'
[System.Diagnostics.Process]::Start($psi) | Out-Null

$found = $null
for ($i = 0; $i -lt ($TimeoutSeconds * 5); $i++) {
    Start-Sleep -Milliseconds 200
    $found = Get-Process $procName -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne 0 -and $before -notcontains $_.Id } | Select-Object -First 1
    if ($found) { break }
}

Remove-Item -LiteralPath $stub -Force -ErrorAction SilentlyContinue

if ($found) {
    Write-Host ("PASS  GUI window appeared from the hidden chain ({0} pid {1}, title '{2}')" -f $procName, $found.Id, $found.MainWindowTitle) -ForegroundColor Green
    Start-Sleep -Milliseconds 300
    Stop-Process -Id $found.Id -Force -ErrorAction SilentlyContinue
    exit 0
}
Write-Host ("FAIL  no {0} window appeared from the hidden chain" -f $procName) -ForegroundColor Red
exit 1
