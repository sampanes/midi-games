[CmdletBinding()]
param(
    [switch]$Quiet
)

# Stops every node process running this repository's MIDI listener server.
# Match the resolved script path so another checkout with the same script name
# cannot be stopped accidentally.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$serverScript = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'serve-midi-listener.mjs'))
$serverScriptWithForwardSlashes = $serverScript.Replace('\', '/')
$listeners = @(Get-CimInstance Win32_Process -Filter "Name = 'node.exe'" |
    Where-Object {
        $_.CommandLine -and (
            $_.CommandLine.IndexOf($serverScript, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.CommandLine.IndexOf($serverScriptWithForwardSlashes, [StringComparison]::OrdinalIgnoreCase) -ge 0
        )
    })

if ($listeners.Count -eq 0) {
    if (-not $Quiet) { Write-Host '[OK] No MIDI listener server is running.' }
    return
}

foreach ($listener in $listeners) {
    try {
        Stop-Process -Id $listener.ProcessId -Force -ErrorAction Stop
        if (-not $Quiet) { Write-Host "[OK] Stopped MIDI listener server (PID $($listener.ProcessId))." }
    }
    catch {
        Write-Warning "Could not stop MIDI listener server PID $($listener.ProcessId): $($_.Exception.Message)"
    }
}
