[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765
)

# Reports whether this repository's MIDI listener server is running and what
# owns the listener port.

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
    Write-Host '[--] MIDI listener server is not running.'
}
else {
    foreach ($listener in $listeners) {
        Write-Host "[OK] MIDI listener server is running (PID $($listener.ProcessId))."
    }
}

$portOwners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique)
if ($portOwners.Count -eq 0) {
    Write-Host "[--] Nothing is listening on port $Port."
}
else {
    foreach ($owner in $portOwners) {
        $name = (Get-Process -Id $owner -ErrorAction SilentlyContinue).ProcessName
        Write-Host "[..] Port $Port is held by PID $owner ($name). URL: http://127.0.0.1:$Port/midi-listener/"
    }
}
