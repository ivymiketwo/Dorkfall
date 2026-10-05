@echo off
rem Double-click to get the latest changes from GitHub and play the game.
rem If Godot moves, change the path on the next line.
set "GODOT=%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe"

rem The unzipped download is often a folder with this name, with the real Godot inside it.
if exist "%GODOT%\" for %%F in ("%GODOT%\Godot*_win64.exe") do set "GODOT=%%~fF"

cd /d "%~dp0"
set "FOUND=1"
if not exist "%GODOT%" set "FOUND="
if exist "%GODOT%\" set "FOUND="
if not defined FOUND (
  echo Godot program not found at: %GODOT%
  echo Edit update_and_play.bat and fix the path.
  pause
  exit /b 1
)

echo Getting the latest changes...
rem The Godot editor rewrites project.godot by itself, which would block the update.
rem Keep a copy of the local version (project.godot.local-backup), then use the shared one.
git diff --quiet -- project.godot
if errorlevel 1 (
  copy /y project.godot project.godot.local-backup >nul
  git checkout -- project.godot
  echo Godot had changed project.godot - saved a copy as project.godot.local-backup
)
rem Godot also rewrites its .import files (notes about each picture/sound) on its own.
rem They are generated, never edited by hand, so take the shared versions.
git checkout -- "*.import" 2>nul
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
