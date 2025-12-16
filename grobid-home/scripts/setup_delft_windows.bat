@echo off
REM GROBID DeLFT Setup Script for Windows
REM This batch file runs the PowerShell setup script.
REM Run from the GROBID root directory.

echo ============================================================
echo GROBID DeLFT Setup for Windows
echo ============================================================
echo.
echo This will set up the Deep Learning (DeLFT) environment.
echo.

REM Check if we're in the GROBID root directory
if not exist "grobid-home\config\grobid.yaml" (
    echo ERROR: Please run this script from the GROBID root directory.
    echo.
    echo Expected: grobid-home\config\grobid.yaml
    echo Current:  %CD%
    echo.
    pause
    exit /b 1
)

REM Run the PowerShell script
powershell -ExecutionPolicy Bypass -File "%~dp0setup_delft_windows.ps1" %*

if %ERRORLEVEL% neq 0 (
    echo.
    echo Setup encountered errors. Please review the output above.
)

echo.
pause

