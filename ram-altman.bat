@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0ram-altman-windows.ps1" %*
exit /b %ERRORLEVEL%
