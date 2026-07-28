@echo off
call "%~dp0Restore-Config.cmd" %*
set "RC=%errorlevel%"
echo.
echo Press any key to close this window...
pause >nul
exit /b %RC%
