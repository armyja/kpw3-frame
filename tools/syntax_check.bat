@echo off
rem Static syntax check for the Kindle shell scripts (uses Git Bash if present).
setlocal
set BASH="C:\Program Files\Git\bin\bash.exe"
if not exist %BASH% (
  echo Git Bash not found, skipping syntax check
  exit /b 0
)
set FAILED=0
for %%f in ("%~dp0..\kindle\screensaver\*.sh") do (
  %BASH% -n "%%f"
  if errorlevel 1 (
    echo FAIL %%f
    set FAILED=1
  ) else (
    echo OK   %%~nxf
  )
)
if "%FAILED%"=="1" exit /b 1
echo all scripts parsed OK
