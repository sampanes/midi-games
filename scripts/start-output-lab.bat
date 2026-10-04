@echo off
rem Starts the MIDI output lab page (stops any previous listener server first).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-MidiListener.ps1" -Page output-lab %*
