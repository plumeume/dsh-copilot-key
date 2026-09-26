# Rebuilds DshCopilotKey.exe from source using the in-box C# compiler (no SDK required).
$ErrorActionPreference = 'Stop'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { throw "csc.exe not found at $csc" }
$src = Join-Path $PSScriptRoot 'DshCopilotKey.cs'
$out = Join-Path $PSScriptRoot 'DshCopilotKey.exe'
& $csc /nologo /target:winexe /out:$out /r:System.Windows.Forms.dll $src
if ($LASTEXITCODE -ne 0) { throw "compile failed ($LASTEXITCODE)" }
Write-Host "built $out"
