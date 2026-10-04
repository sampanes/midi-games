@echo off
rem Stops any running MIDI listener server.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop-MidiListener.ps1" %*
