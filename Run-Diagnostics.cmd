@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -File "%~dp0Start-Here.ps1" -Action Diagnose -TestSafe %*
set "RC=%errorlevel%"
endlocal & exit /b %RC%
