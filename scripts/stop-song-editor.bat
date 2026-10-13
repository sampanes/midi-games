@echo off
rem Stops the song editor server.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop-SongEditor.ps1" %*
