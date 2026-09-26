# Installs the Copilot-key remap: registers a logon scheduled task that runs the watcher.
$ErrorActionPreference = 'Stop'
$dir  = $PSScriptRoot
$exe  = Join-Path $dir 'DshCopilotKey.exe'
if (-not (Test-Path $exe)) { throw "missing $exe (run build.ps1 first)" }

# Pin an explicit HIGH integrity label on the watcher binary. Two reasons:
#  1) A low-level keyboard hook only sees keys typed into windows of the same or lower
#     integrity, so the hook must run High to keep working while an elevated window has focus.
#  2) On 2026-09-23 a stray Low label on C:\dsh was inherited by this exe and dragged the whole
#     chain (watcher -> cmd -> powershell -> node) down to Low; Low cannot write the Medium
#     %USERPROFILE%\.dsh, so "dsh web" died with "EPERM ... profiles\web\cordis.yml".
#     An explicit label is NOT inherited from the parent directory, so that cannot happen again.
# Note: with a High label on the exe, rebuilding it (build.ps1) needs an elevated shell.
icacls $exe /setintegritylevel High | Out-Null

$taskName = 'DshCopilotKey'
$user     = "$env:USERDOMAIN\$env:USERNAME"
$action   = New-ScheduledTaskAction -Execute $exe -Argument 'watch' -WorkingDirectory $dir
$trigger  = New-ScheduledTaskTrigger -AtLogOn -User $user
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero)
$settings.RestartCount = 3
$settings.RestartInterval = 'PT1M'   # ISO-8601 duration; Task Scheduler rejects a raw TimeSpan here

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$level = if ($isAdmin) { 'Highest' } else { 'Limited' }
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel $level

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Write-Host "registered scheduled task '$taskName' (run level: $level, at logon)"

Start-ScheduledTask -TaskName $taskName
Start-Sleep -Seconds 2
Write-Host "watcher running: " ([bool](Get-Process DshCopilotKey -ErrorAction SilentlyContinue))
Write-Host "log: " (Join-Path $dir 'watcher.log')
