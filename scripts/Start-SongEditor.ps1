[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8766,
    # Open the editor in a browser on every phone adb can see.
    [switch]$Phone,
    [ValidateSet('chrome', 'brave')]
    [string]$Browser = 'chrome',
    # Open the editor in this PC's default browser.
    [switch]$Pc
)

# Starts the song editor server (scripts/song-editor.py) in the background,
# listening on 127.0.0.1 only. Phones reach it through "adb reverse", which
# makes the phone's own localhost:PORT lead to this PC. Idempotent: a running
# editor is stopped first. Stop it with scripts\stop-song-editor.bat.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$serverScript = Join-Path $PSScriptRoot 'song-editor.py'
$pythonCommand = Get-Command python -ErrorAction Stop
$url = "http://localhost:$Port/"
$packages = @{ chrome = 'com.android.chrome'; brave = 'com.brave.browser' }

& (Join-Path $PSScriptRoot 'Stop-SongEditor.ps1') -Quiet

$portOwner = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty OwningProcess
if ($portOwner) {
    $ownerName = (Get-Process -Id $portOwner -ErrorAction SilentlyContinue).ProcessName
    throw "Port $Port is held by another program (PID $portOwner, $ownerName). Stop it or pass -Port."
}

$quotedServerScript = '"' + $serverScript.Replace('"', '\"') + '"'
$server = Start-Process `
    -FilePath $pythonCommand.Source `
    -ArgumentList @($quotedServerScript, '--port', [string]$Port) `
    -WorkingDirectory $repositoryRoot `
    -WindowStyle Hidden `
    -PassThru

$ready = $false
for ($attempt = 0; $attempt -lt 50; $attempt++) {
    if ($server.HasExited) {
        throw "The song editor exited before it became ready (exit code $($server.ExitCode))."
    }
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/" -UseBasicParsing -TimeoutSec 1
        if ($response.StatusCode -eq 200) {
            $ready = $true
            break
        }
    }
    catch {
        Start-Sleep -Milliseconds 200
    }
}
if (-not $ready) {
    throw "The song editor did not become ready at $url"
}
Write-Host "[OK] Song editor running at $url (PID $($server.Id))."

$adb = Get-Command adb -ErrorAction SilentlyContinue
if ($adb) {
    $devices = @(& $adb.Source devices | Select-Object -Skip 1 |
        Where-Object { $_ -match '^(\S+)\s+device$' } |
        ForEach-Object { ($_ -split '\s+')[0] })
    foreach ($device in $devices) {
        & $adb.Source -s $device reverse "tcp:$Port" "tcp:$Port" | Out-Null
        Write-Host "[OK] Phone $device can open $url"
        if ($Phone) {
            & $adb.Source -s $device shell am start -a android.intent.action.VIEW -d $url -p $packages[$Browser] | Out-Null
            Write-Host "[OK] Opened it in $Browser on $device."
        }
    }
    if ($devices.Count -eq 0) {
        Write-Host '[!] No phone connected over adb; only this PC can open the editor.'
    }
}
else {
    Write-Host '[!] adb not found; only this PC can open the editor.'
}

if ($Pc) {
    Start-Process $url | Out-Null
}
Write-Host 'Stop it with scripts\stop-song-editor.bat; check it with scripts\song-editor-status.bat.'
