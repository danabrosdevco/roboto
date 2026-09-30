@echo off
rem Double-click to export the next playtest build to ..\Exports.
rem What it does, and its options, are at the top of export.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0export.ps1" %*
echo.
pause
