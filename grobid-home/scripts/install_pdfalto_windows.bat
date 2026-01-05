@echo off
setlocal

REM Installs official pdfalto 0.4 on Windows into grobid-home\pdfalto\win-64\pdfalto
REM Usage (from repo root):
REM   grobid-home\scripts\install_pdfalto_windows.bat

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_pdfalto_windows.ps1" %*
exit /b %ERRORLEVEL%

@echo off
setlocal

REM Installs official pdfalto 0.4 Windows bundle into grobid-home\pdfalto\win-64\pdfalto and verifies SHA256.
REM Usage:
REM   grobid-home\scripts\install_pdfalto_windows.bat

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_pdfalto_windows.ps1" %*
exit /b %ERRORLEVEL%




REM Installs official pdfalto 0.4 on Windows into grobid-home\pdfalto\win-64\pdfalto
REM Usage (from repo root):
REM   grobid-home\scripts\install_pdfalto_windows.bat

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_pdfalto_windows.ps1" %*
exit /b %ERRORLEVEL%

@echo off
setlocal

REM Installs official pdfalto 0.4 Windows bundle into grobid-home\pdfalto\win-64\pdfalto and verifies SHA256.
REM Usage:
REM   grobid-home\scripts\install_pdfalto_windows.bat

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_pdfalto_windows.ps1" %*
exit /b %ERRORLEVEL%


