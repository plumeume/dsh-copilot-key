# Regression test for the "no console window" behaviour: triggers the key once and records every
# top-level window that appears while it runs. Windows are identified by pid + HWND, so a window
# whose *title* changes is not mistaken for a new window.
#
#   powershell -ExecutionPolicy Bypass -File test\windowwatch.ps1 -Seconds 10
#
# PASS = "console/terminal windows opened: 0". Before the CREATE_NO_WINDOW fix this printed the
# Windows Terminal window that the key used to throw over the screen.
param([int]$Seconds = 10, [int]$TriggerAfterMs = 1500, [switch]$NoTrigger)

$exe = Join-Path (Split-Path $PSScriptRoot -Parent) 'DshCopilotKey.exe'
if (-not (Test-Path $exe)) { throw "missing $exe - run build.ps1 first" }
$consoleHosts = @('cmd', 'conhost', 'WindowsTerminal', 'OpenConsole', 'powershell', 'pwsh', 'wt')

function Snap {
    Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object {
        [pscustomobject]@{
            Key   = '{0}|{1}' -f $_.Id, $_.MainWindowHandle.ToInt64()
            Proc  = $_.ProcessName
            Title = $_.MainWindowTitle
            Hwnd  = $_.MainWindowHandle.ToInt64()
        }
    }
}

$known = @{}
foreach ($s in Snap) { $known[$s.Key] = $s }
Write-Host ('baseline visible windows: ' + $known.Count)
foreach ($k in $known.Keys) { Write-Host ('  = {0} hwnd=0x{1:X} "{2}"' -f $known[$k].Proc, $known[$k].Hwnd, $known[$k].Title) }

$t0 = Get-Date
$events = New-Object System.Collections.Generic.List[string]
$triggered = [bool]$NoTrigger
while (((Get-Date) - $t0).TotalMilliseconds -lt ($Seconds * 1000)) {
    $now = ((Get-Date) - $t0).TotalMilliseconds
    if (-not $triggered -and $now -ge $TriggerAfterMs) {
        $triggered = $true
        $events.Add(('{0,7:N0}ms  TRIGGER (DshCopilotKey.exe trigger)' -f $now))
        & $exe trigger | Out-Null
    }
    foreach ($s in Snap) {
        if (-not $known.ContainsKey($s.Key)) {
            $known[$s.Key] = $s
            $kind = if ($consoleHosts -contains $s.Proc) { 'CONSOLE WINDOW' } else { 'new window' }
            $events.Add(('{0,7:N0}ms  + {1}  {2} hwnd=0x{3:X} "{4}"' -f $now, $kind, $s.Proc, $s.Hwnd, $s.Title))
        } elseif ($known[$s.Key].Title -ne $s.Title) {
            $events.Add(('{0,7:N0}ms    title change on existing {1} hwnd=0x{2:X} "{3}" -> "{4}"' -f $now, $s.Proc, $s.Hwnd, $known[$s.Key].Title, $s.Title))
            $known[$s.Key].Title = $s.Title
        }
    }
}

Write-Host ''
Write-Host '--- timeline ---'
if ($events.Count -eq 0) { Write-Host '  (nothing changed at all)' }
foreach ($e in $events) { Write-Host ('  ' + $e) }
$consoles = @($events | Where-Object { $_.Contains('CONSOLE WINDOW') })
$news     = @($events | Where-Object { $_.Contains('+ new window') })
Write-Host ''
Write-Host ('console/terminal windows opened: ' + $consoles.Count + '   other new windows: ' + $news.Count)
if ($consoles.Count -eq 0) { Write-Host 'RESULT: PASS - no console/terminal window appeared' -ForegroundColor Green; exit 0 }
Write-Host 'RESULT: FAIL - a console/terminal window appeared' -ForegroundColor Red
exit 1
