@echo off
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -File "%~dp0Start-Here.ps1" -Action Install -TestSafe %*
set "RC=%errorlevel%"
endlocal & exit /b %RC%
