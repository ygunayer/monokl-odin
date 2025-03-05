@echo off

set FLAGS=-out=bin/monokl.exe
set COMMAND=

for %%i in (%*) do (
  if "%%i"=="run" set COMMAND=run
  if "%%i"=="build" set COMMAND=build
  if "%%i"=="--debug" set FLAGS=%FLAGS% -o:none -debug
  if "%%i"=="-d" set FLAGS=%FLAGS% -o:none -debug
)

if defined COMMAND (
  odin %COMMAND% src %FLAGS%
  exit /b %errorlevel%
)

echo Usage: %~nx0 ^<command^> [flags...]
echo.
echo Commands:
echo    run            Builds and runs the project
echo    build          Builds the project
echo.
echo Optional flags:
echo    --debug, -d    Enables debug mode and disables optimizations
exit /b 1
