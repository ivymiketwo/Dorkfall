@echo off
rem Double-click to get the latest changes from GitHub and open the project in the Godot editor.
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
  echo Edit update_and_edit.bat and fix the path.
  pause
  exit /b 1
)

echo Getting the latest changes...
rem The Godot editor rewrites project.godot by itself, which would block the update.
rem Keep a copy of the local version (project.godot.local-backup), then use the shared one.
rem (Always put the shared copy back: a change of line endings alone can block the update
rem without "git diff" noticing it.)
git diff --quiet -- project.godot
if errorlevel 1 (
  copy /y project.godot project.godot.local-backup >nul
  echo Godot had changed project.godot - saved a copy as project.godot.local-backup
)
git checkout -- project.godot
rem Godot also rewrites its .import files (notes about each picture/sound) on its own.
rem They are generated, never edited by hand, so take the shared versions.
git checkout -- "*.import" 2>nul
git pull --ff-only
if errorlevel 1 (
  rem one more try after putting back the files Godot rewrites by itself
  git checkout -- project.godot "*.import" 2>nul
  git pull --ff-only
)
if errorlevel 1 (
  echo.
  echo Could not update. Usually this means a file here was changed by hand.
  echo Ask Claude for help, or press a key to open the current version anyway.
  pause
)

echo Opening the editor...
start "" "%GODOT%" --path . --editor
