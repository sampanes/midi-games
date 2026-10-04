[CmdletBinding()]
param(
    # Skip the Program Change trials, which leave the synth on program 0.
    [switch]$SkipProgramChange,
    # Exact DirectShow name of the keyboard's USB audio input, and a -like
    # pattern matching its MIDI output port names. When omitted they are read
    # from the ignored private/local-device.json:
    #   { "audioDevice": "Microphone (...)", "portPattern": "Keyboard Name*" }
    [string]$AudioDevice,
    [string]$PortPattern
)

# Unattended output probe. Sends quiet MIDI to every keyboard output while
# recording the keyboard's own USB audio input, then measures which
# port/channel plays the built-in synth, its tuning, velocity and CC7 volume
# response, and whether Program Change alters the sound.
#
# Requirements: keyboard on USB with PATCH on, nobody touching it while it
# runs, ffmpeg on PATH, Python with numpy. Results go to private/midi/.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$analyzer = Join-Path $PSScriptRoot 'analyze-auto-probe.py'
$resultDirectory = Join-Path $repositoryRoot 'private\midi'
$workDirectory = Join-Path $repositoryRoot 'private\tmp\auto-probe'
$localDeviceFile = Join-Path $repositoryRoot 'private\local-device.json'
if ((-not $AudioDevice -or -not $PortPattern) -and (Test-Path -LiteralPath $localDeviceFile)) {
    $localDevice = Get-Content -LiteralPath $localDeviceFile -Raw | ConvertFrom-Json
    if (-not $AudioDevice) { $AudioDevice = $localDevice.audioDevice }
    if (-not $PortPattern) { $PortPattern = $localDevice.portPattern }
}
if (-not $AudioDevice -or -not $PortPattern) {
    throw "Pass -AudioDevice and -PortPattern, or create $localDeviceFile with audioDevice and portPattern."
}
$audioDevice = $AudioDevice
$portPattern = $PortPattern
$recordingTag = 'midi-games-auto-probe'
$velocity = 24
[IO.Directory]::CreateDirectory($resultDirectory) | Out-Null
[IO.Directory]::CreateDirectory($workDirectory) | Out-Null
$stamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH-mm-ssZ')

function Stop-ProbeRecorders {
    Get-CimInstance Win32_Process -Filter "Name = 'ffmpeg.exe'" |
        Where-Object { $_.CommandLine -and $_.CommandLine.Contains($recordingTag) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

# ---- Preflight -------------------------------------------------------------
Stop-ProbeRecorders
$ffmpeg = (Get-Command ffmpeg -ErrorAction Stop).Source
$python = (Get-Command python -ErrorAction Stop).Source
& $python -c "import numpy" 2>$null
if ($LASTEXITCODE -ne 0) { throw 'Python numpy is required (python -m pip install numpy).' }
# ffmpeg prints the device list on stderr; run through cmd so PowerShell 5.1
# does not turn those lines into terminating errors.
$deviceList = (cmd /c 'ffmpeg -hide_banner -list_devices true -f dshow -i dummy 2>&1' | Out-String)
if (-not $deviceList.Contains($audioDevice)) { throw "Audio input '$audioDevice' not found. Is the keyboard on USB?" }

Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime]
$null = [Windows.Devices.Midi.MidiOutPort, Windows.Devices.Midi, ContentType = WindowsRuntime]
$asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() |
    Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } |
    Select-Object -First 1
function Wait-WinRt($operation, [type]$resultType) {
    $task = $asTask.MakeGenericMethod($resultType).Invoke($null, @($operation))
    $task.Wait(-1) | Out-Null
    $task.Result
}

$selector = [Windows.Devices.Midi.MidiOutPort]::GetDeviceSelector()
$found = Wait-WinRt ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync($selector)) ([Windows.Devices.Enumeration.DeviceInformationCollection])
$portInfos = @($found | Where-Object { $_.Name -like $portPattern } | Sort-Object Name)
if ($portInfos.Count -eq 0) { throw "No MIDI outputs match '$portPattern'." }
$outputs = [ordered]@{}
foreach ($info in $portInfos) {
    $port = Wait-WinRt ([Windows.Devices.Midi.MidiOutPort]::FromIdAsync($info.Id)) ([Windows.Devices.Midi.IMidiOutPort])
    if ($port) { $outputs[$info.Name] = $port } else { Write-Warning "Could not open $($info.Name)" }
}
# Sorted port names put the first USB port first; it carries the marker note.
$markerPort = @($outputs.Keys)[0]

# ---- MIDI helpers ----------------------------------------------------------
function Send-Note($port, [int]$channel, [int]$note, [int]$noteVelocity, [int]$holdMs) {
    $ch = [byte]($channel - 1)
    $port.SendMessage((New-Object Windows.Devices.Midi.MidiNoteOnMessage($ch, [byte]$note, [byte]$noteVelocity)))
    Start-Sleep -Milliseconds $holdMs
    $port.SendMessage((New-Object Windows.Devices.Midi.MidiNoteOffMessage($ch, [byte]$note, [byte]0)))
}
function Send-Cc($port, [int]$channel, [int]$controller, [int]$value) {
    $port.SendMessage((New-Object Windows.Devices.Midi.MidiControlChangeMessage([byte]($channel - 1), [byte]$controller, [byte]$value)))
}
function Send-Silence {
    foreach ($port in $outputs.Values) {
        for ($c = 1; $c -le 16; $c++) { Send-Cc $port $c 123 0; Send-Cc $port $c 120 0 }
    }
}

# Performs one planned step: optional setup message, then a short note.
# Returns the event record with its send time.
function Invoke-Step([hashtable]$step, $clock) {
    $port = $outputs[$step.port]
    $channel = [int]$step.channel
    if ($step.ContainsKey('cc7')) { Send-Cc $port $channel 7 $step.cc7 }
    if ($step.ContainsKey('program')) {
        if ($null -eq $step.program) {
            Send-Cc $port $channel 7 100
        }
        else {
            $port.SendMessage((New-Object Windows.Devices.Midi.MidiProgramChangeMessage([byte]($channel - 1), [byte]$step.program)))
            Start-Sleep -Milliseconds 300
        }
    }
    $event = @{} + $step
    $event.t = $clock.Elapsed.TotalSeconds
    Send-Note $port $channel ([int]$step.note) ([int]$step.velocity) 400
    $event
}

# Runs one recorded phase over a list of step hashtables. Times are seconds
# since the recording process started.
function Invoke-Phase([string]$phase, [object[]]$plan, [double]$secondsPerStep) {
    $wav = Join-Path $workDirectory "$stamp-$phase.wav"
    $scheduleFile = Join-Path $workDirectory "$stamp-$phase-schedule.json"
    $resultFile = Join-Path $workDirectory "$stamp-$phase-result.json"
    $duration = [int][Math]::Ceiling(5 + $plan.Count * $secondsPerStep + 3)
    # Launch directly: Start-Process can stall for a long time on this machine.
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $ffmpeg
    $startInfo.Arguments = "-hide_banner -loglevel error -f dshow -i audio=`"$audioDevice`" -t $duration -ac 1 -ar 44100 -metadata comment=$recordingTag -y `"$wav`""
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardError = $true
    $recorder = [Diagnostics.Process]::Start($startInfo)
    $recorderErrors = $recorder.StandardError.ReadToEndAsync()
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $events = New-Object System.Collections.Generic.List[object]
    try {
        Start-Sleep -Milliseconds 3000
        $events.Add(@{ kind = 'marker'; port = $markerPort; t = $clock.Elapsed.TotalSeconds })
        Send-Note $outputs[$markerPort] 1 72 32 300
        Start-Sleep -Milliseconds 1700
        foreach ($step in $plan) {
            $event = Invoke-Step $step $clock
            $events.Add($event)
            $remaining = [int]($secondsPerStep * 1000 - ($clock.Elapsed.TotalSeconds - $event.t) * 1000)
            if ($remaining -gt 0) { Start-Sleep -Milliseconds $remaining }
        }
        Send-Silence
        if (-not $recorder.WaitForExit(($duration + 20) * 1000)) { throw "Recorder for $phase did not finish." }
        if ($recorder.ExitCode -ne 0) { throw "Recorder for $phase failed: $($recorderErrors.Result)" }
    }
    finally {
        if (-not $recorder.HasExited) { Stop-Process -Id $recorder.Id -Force }
    }
    @{ events = $events } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $scheduleFile -Encoding UTF8
    & $python $analyzer $phase $wav $scheduleFile $resultFile
    if ($LASTEXITCODE -ne 0) { throw "Analyzer failed for $phase." }
    Get-Content -LiteralPath $resultFile -Raw | ConvertFrom-Json
}

$report = [ordered]@{
    kind = 'auto-probe'
    schemaVersion = 1
    startedAt = (Get-Date).ToUniversalTime().ToString('o')
    outputs = @($outputs.Keys)
    velocityCap = 32
}

try {
    Write-Host "[..] Phase 1: every output x channel ($($outputs.Count * 16) notes). Do not touch the keyboard."
    $matrixPlan = foreach ($name in $outputs.Keys) {
        foreach ($channel in 1..16) { @{ kind = 'matrix'; port = $name; channel = $channel; note = 60; velocity = $velocity } }
    }
    $matrix = Invoke-Phase 'matrix' @($matrixPlan) 1.4
    $report.matrix = $matrix
    if (-not $matrix.markerFound) {
        throw 'No synth sound at all. Turn PATCH on, check the PARA volume, then run again.'
    }
    $sounding = @($matrix.trials | Where-Object { $_.sounded })
    Write-Host "[OK] $($sounding.Count) of $(@($matrix.trials).Count) port/channel combinations made sound."
    if ($sounding.Count -eq 0) { throw 'The marker sounded but no matrix trial did; see the matrix result.' }

    $target = $sounding[0]
    $port = $target.port
    $channel = [int]$target.channel
    Write-Host "[..] Phase 2: detail tests on $port channel $channel."
    $detailPlan = New-Object System.Collections.Generic.List[object]
    $base = @{ port = $port; channel = $channel; note = 60; velocity = $velocity }
    foreach ($note in 36, 48, 60, 72, 84) { $step = $base + @{ kind = 'pitch' }; $step.note = $note; $detailPlan.Add($step) }
    foreach ($v in 4, 12, 20, 32) { $step = $base + @{ kind = 'velocity' }; $step.velocity = $v; $detailPlan.Add($step) }
    foreach ($volume in 127, 64, 20) { $detailPlan.Add(($base + @{ kind = 'cc7'; cc7 = $volume })) }
    if (-not $SkipProgramChange) {
        # The first program trial (program = null) restores CC7 and records the
        # current sound as the baseline fingerprint.
        $detailPlan.Add(($base + @{ kind = 'program'; program = $null }))
        foreach ($program in 1, 2, 3, 0) { $detailPlan.Add(($base + @{ kind = 'program'; program = $program })) }
    }
    $detail = Invoke-Phase 'detail' @($detailPlan.ToArray()) 1.6
    Send-Cc $outputs[$port] $channel 7 100
    $report.detailTarget = @{ port = $port; channel = $channel }
    $report.detail = $detail
    $report.finishedAt = (Get-Date).ToUniversalTime().ToString('o')
    $report.stateLeftBehind = if ($SkipProgramChange) { 'CC7 set to 100 on the target channel.' } else { 'CC7 set to 100 and Program Change 0 on the target channel.' }
}
catch {
    $report.error = $_.Exception.Message
    Write-Warning $report.error
}
finally {
    try { Send-Silence } catch { Write-Warning "Cleanup send failed: $($_.Exception.Message)" }
    foreach ($port in $outputs.Values) { try { $port.Dispose() } catch { } }
    Stop-ProbeRecorders
    $jsonPath = Join-Path $resultDirectory "auto-probe-$stamp.json"
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    Write-Host "[OK] Results: $jsonPath"
    Write-Host "     Recordings: $workDirectory"
}
