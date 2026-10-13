[CmdletBinding()]
param(
    [switch]$Quiet,
    # Only say whether the editor is running.
    [switch]$Status
)

# Stops every python process running this repository's song editor server.
# Matches the resolved script path, so other Python programs are left alone.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$serverScript = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'song-editor.py'))
$serverScriptWithForwardSlashes = $serverScript.Replace('\', '/')
$editors = @(Get-CimInstance Win32_Process -Filter "Name = 'python.exe'" |
    Where-Object {
        $_.CommandLine -and (
            $_.CommandLine.IndexOf($serverScript, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $_.CommandLine.IndexOf($serverScriptWithForwardSlashes, [StringComparison]::OrdinalIgnoreCase) -ge 0
        )
    })

if ($Status) {
    if ($editors.Count -eq 0) {
        Write-Host '[OK] The song editor is not running.'
    }
    foreach ($editor in $editors) {
        Write-Host "[OK] The song editor is running (PID $($editor.ProcessId)): $($editor.CommandLine)"
    }
    return
}

if ($editors.Count -eq 0) {
    if (-not $Quiet) { Write-Host '[OK] The song editor was not running.' }
    return
}

foreach ($editor in $editors) {
    try {
        Stop-Process -Id $editor.ProcessId -Force -ErrorAction Stop
        if (-not $Quiet) { Write-Host "[OK] Stopped the song editor (PID $($editor.ProcessId))." }
    }
    catch {
        Write-Warning "Could not stop the song editor PID $($editor.ProcessId): $($_.Exception.Message)"
    }
}
