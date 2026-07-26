@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Start-Here.ps1" -Action Install -Live %*
set "RC=%errorlevel%"
endlocal & exit /b %RC%
