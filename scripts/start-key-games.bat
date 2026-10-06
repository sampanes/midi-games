@echo off
rem Starts the Key Games app (Flutter, Windows build) full screen.
rem Stops any previous copy first. Alt+F4 or scripts\stop-key-games.bat quits.
rem Check it is running: tasklist /FI "IMAGENAME eq key_games.exe"
rem Add --windowed for a normal window, e.g. start-key-games.bat --windowed
set "EXE=%~dp0..\apps\key_games\build\windows\x64\runner\Release\key_games.exe"
if not exist "%EXE%" (
  echo [X] Not built yet. Run in apps\key_games:  flutter build windows --release
  exit /b 1
)
taskkill /IM key_games.exe /F >nul 2>&1
start "key-games" "%EXE%" %*
echo [OK] Key Games started. Close any browser MIDI page first; Windows lets only one program use the keyboard.
