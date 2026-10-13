@echo off
rem Says whether the song editor server is running.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop-SongEditor.ps1" -Status
