@echo off
rem Builds dist\SyncDood.exe (a single file with everything inside). Double-click. No administrator rights needed.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Build.ps1"
echo.
pause
