@echo off
rem Starts the Color Keys game (stops any previous listener server first).
rem Stop it with Ctrl+C here or scripts\stop-midi-listener.bat.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-MidiListener.ps1" -Page color-keys %*
