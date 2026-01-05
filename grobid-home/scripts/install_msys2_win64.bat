@echo off
setlocal

REM Installs MSYS2 to C:\msys64 (required to build pdfalto from source on Windows).
REM Maintainer-only helper.
REM
REM We delegate to PowerShell to avoid cmd.exe quirks in this environment.

set SCRIPT_DIR=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%install_msys2_win64.ps1" -VerboseLogging -TarballOnly
if errorlevel 1 exit /b 1

endlocal

