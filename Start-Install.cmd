@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Here.ps1" -Action Install -TestSafe %*
set "RC=%errorlevel%"
endlocal & exit /b %RC%
