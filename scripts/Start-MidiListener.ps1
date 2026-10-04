[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765,
    [ValidateSet('WinRT', 'Default')]
    [string]$MidiBackend = 'WinRT'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$serverScript = Join-Path $PSScriptRoot 'serve-midi-listener.mjs'
$nodeCommand = Get-Command node -ErrorAction Stop
$listenerUrl = "http://127.0.0.1:$Port/midi-listener/"
$serverProcess = $null
$quotedServerScript = '"' + $serverScript.Replace('"', '\"') + '"'

# Idempotent start: a previous server can survive if its terminal was closed
# instead of stopped with Ctrl+C, and would hold the port.
& (Join-Path $PSScriptRoot 'Stop-MidiListener.ps1') -Quiet

$portOwner = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1 -ExpandProperty OwningProcess
if ($portOwner) {
    $ownerName = (Get-Process -Id $portOwner -ErrorAction SilentlyContinue).ProcessName
    throw "Port $Port is held by another program (PID $portOwner, $ownerName). Stop it or pass -Port."
}

try {
    $serverProcess = Start-Process `
        -FilePath $nodeCommand.Source `
        -ArgumentList @($quotedServerScript, '--port', [string]$Port) `
        -WorkingDirectory $repositoryRoot `
        -WindowStyle Hidden `
        -PassThru

    $ready = $false
    for ($attempt = 0; $attempt -lt 50; $attempt++) {
        if ($serverProcess.HasExited) {
            throw "The local MIDI listener server exited before it became ready. Port $Port may already be in use."
        }

        try {
            $response = Invoke-WebRequest -Uri $listenerUrl -UseBasicParsing -TimeoutSec 1
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
        throw "The local MIDI listener did not become ready at $listenerUrl"
    }

    $browserCandidates = @(
        'C:\Program Files\Google\Chrome\Application\chrome.exe',
        'C:\Program Files (x86)\Google\Chrome\Application\chrome.exe',
        'C:\Program Files\Microsoft\Edge\Application\msedge.exe',
        'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe'
    )
    $browser = $browserCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

    if ($browser) {
        $profileName = if ($MidiBackend -eq 'WinRT') { 'chromium-winrt-midi' } else { 'chromium-default-midi' }
        $browserProfile = Join-Path $repositoryRoot "private\browser-profiles\$profileName"
        [IO.Directory]::CreateDirectory($browserProfile) | Out-Null
        $quotedBrowserProfile = '"' + $browserProfile.Replace('"', '\"') + '"'
        $browserArguments = @(
            "--user-data-dir=$quotedBrowserProfile",
            '--new-window',
            '--no-first-run',
            '--no-default-browser-check',
            '--disable-sync'
        )
        if ($MidiBackend -eq 'WinRT') {
            $browserArguments += '--enable-features=MidiManagerWinrt'
        }
        $browserArguments += $listenerUrl
        Start-Process -FilePath $browser -ArgumentList $browserArguments | Out-Null
    }
    else {
        if ($MidiBackend -eq 'WinRT') {
            throw 'Chrome or Edge is required to launch the Windows Runtime MIDI backend.'
        }
        Start-Process $listenerUrl | Out-Null
    }

    Write-Host "MIDI listener opened at $listenerUrl"
    Write-Host "MIDI backend: $MidiBackend"
    Write-Host 'Click Enable MIDI in the page, then exercise and optionally label controls at your own pace.'
    Write-Host 'Click Save private inventory when finished. Press Ctrl+C here to stop the local server.'
    Write-Host "Server PID: $($serverProcess.Id). If this window is closed, run scripts\stop-midi-listener.bat."

    Wait-Process -Id $serverProcess.Id
}
finally {
    if ($serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id -Force
    }
}
