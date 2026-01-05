@echo off
setlocal

REM Packages a verified win64 pdfalto folder into a repo-committable ZIP:
REM   grobid-home\pdfalto\win-64\pdfalto-win64-0.4.zip
REM
REM Usage (from repo root):
REM   grobid-home\scripts\package_pdfalto_win64.bat

set SCRIPT_DIR=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%package_pdfalto_win64.ps1"
if errorlevel 1 exit /b 1

endlocal

