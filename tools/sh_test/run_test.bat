@echo off
rem Run the shell-side test (server_interval / save_interval) with Git Bash.
setlocal
set "BASH=C:\Program Files\Git\bin\bash.exe"
if not exist "%BASH%" (
  echo Git Bash not found, cannot run the test
  exit /b 1
)
"%BASH%" "%~dp0server_interval_test.sh" "%~dp0..\.."
exit /b %errorlevel%
