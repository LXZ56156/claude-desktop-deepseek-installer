@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0Start-Here.ps1" -Action Diagnose -Live %*
set "RC=%errorlevel%"
endlocal & exit /b %RC%
