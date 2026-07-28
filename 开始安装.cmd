@echo off
call "%~dp0Start-Install.cmd" %*
set "RC=%errorlevel%"
echo.
echo Press any key to close this window...
pause >nul
exit /b %RC%
