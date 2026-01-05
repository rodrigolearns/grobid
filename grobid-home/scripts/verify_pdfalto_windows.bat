@echo off
setlocal

REM Verifies SHA256 checksums for expected pdfalto 0.4 Windows binaries.
REM Usage (from repo root):
REM   grobid-home\scripts\verify_pdfalto_windows.bat

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify_pdfalto_windows.ps1" %*
exit /b %ERRORLEVEL%

@echo off
setlocal

REM Verifies SHA256 of the locally installed Windows pdfalto bundle (expected pdfalto 0.4).
REM Usage:
REM   grobid-home\scripts\verify_pdfalto_windows.bat

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify_pdfalto_windows.ps1" %*
exit /b %ERRORLEVEL%




REM Verifies SHA256 checksums for expected pdfalto 0.4 Windows binaries.
REM Usage (from repo root):
REM   grobid-home\scripts\verify_pdfalto_windows.bat

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify_pdfalto_windows.ps1" %*
exit /b %ERRORLEVEL%

@echo off
setlocal

REM Verifies SHA256 of the locally installed Windows pdfalto bundle (expected pdfalto 0.4).
REM Usage:
REM   grobid-home\scripts\verify_pdfalto_windows.bat

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify_pdfalto_windows.ps1" %*
exit /b %ERRORLEVEL%


