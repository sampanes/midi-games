@echo off
rem Stops the Key Games app started by start-key-games.bat.
taskkill /IM key_games.exe /F >nul 2>&1
if %ERRORLEVEL%==0 (echo [OK] Key Games stopped.) else (echo [OK] Key Games was not running.)
