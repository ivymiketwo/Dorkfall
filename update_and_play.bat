@echo off
rem Double-click to get the latest changes from GitHub and play the game.
rem If Godot moves, change the path on the next line.
set "GODOT=%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe"

cd /d "%~dp0"
if not exist "%GODOT%" (
  echo Godot not found at: %GODOT%
  echo Edit update_and_play.bat and fix the path.
  pause
  exit /b 1
)

echo Getting the latest changes...
git pull --ff-only
if errorlevel 1 (
  echo.
  echo Could not update. Usually this means a file here was changed by hand.
  echo Ask Claude for help, or press a key to play the current version anyway.
  pause
)

echo Importing new art and sounds...
"%GODOT%" --headless --path . --import

echo Starting the game...
start "" "%GODOT%" --path .
