@echo off
setlocal

REM Wrapper for install_pdfalto_windows.ps1
REM Usage:
REM   grobid-home\scripts\install_pdfalto_windows.bat

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_pdfalto_windows.ps1"
exit /b %ERRORLEVEL%





