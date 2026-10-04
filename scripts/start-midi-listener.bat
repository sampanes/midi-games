@echo off
rem Starts the MIDI listener (stops any previous instance first).
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-MidiListener.ps1" %*
