@echo off
rem Unattended keyboard output probe (about 3 minutes). PATCH on, do not touch the keyboard.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-AutoProbe.ps1" %*
