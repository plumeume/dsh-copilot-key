# Reverts everything: removes the scheduled task and stops the watcher.
$taskName = 'DshCopilotKey'
Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Get-Process DshCopilotKey -ErrorAction SilentlyContinue | Stop-Process -Force
Write-Host 'Copilot key remap removed (key behaves as before again).'
