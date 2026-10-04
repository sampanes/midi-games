@echo off
rem Shows whether the MIDI listener server is running.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Get-MidiListenerStatus.ps1" %*
