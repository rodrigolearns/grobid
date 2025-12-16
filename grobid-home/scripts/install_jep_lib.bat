@echo off
REM install_jep_lib.bat - Windows JEP installation wrapper for GROBID
REM This script calls the PowerShell installer script
REM
REM Usage: Run from grobid root directory:
REM   grobid-home\scripts\install_jep_lib.bat

echo ========================================
echo GROBID JEP Installation Script (Windows)
echo ========================================

REM Check if PowerShell is available
where powershell >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo ERROR: PowerShell is required but not found.
    exit /b 1
)

REM Get the directory where this script is located
set SCRIPT_DIR=%~dp0

REM Run the PowerShell script
powershell -ExecutionPolicy Bypass -File "%SCRIPT_DIR%install_jep_lib.ps1" %*

if %ERRORLEVEL% neq 0 (
    echo.
    echo Installation failed. See errors above.
    exit /b 1
)

echo.
echo Installation completed successfully.


