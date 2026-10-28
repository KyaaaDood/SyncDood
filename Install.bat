@echo off
rem Installs SyncDood (downloads rclone and AutoHotkey v2 portable). Double-click. No administrator rights needed.
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1"
echo.
pause
