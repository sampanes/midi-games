@echo off
rem Starts the song editor server (stops any previous one first).
rem   start-song-editor.bat          server only; phones on adb can open http://localhost:8766/
rem   start-song-editor.bat -Phone   also opens it in Chrome on the phone (-Browser brave for Brave)
rem   start-song-editor.bat -Pc      also opens it on this PC
rem Stop it with scripts\stop-song-editor.bat.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-SongEditor.ps1" %*
