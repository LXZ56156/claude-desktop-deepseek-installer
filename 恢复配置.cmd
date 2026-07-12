@echo off
call "%~dp0Restore-Config.cmd" %*
exit /b %errorlevel%
