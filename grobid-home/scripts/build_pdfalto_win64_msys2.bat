@echo off
setlocal

REM Maintainer script: build pdfalto tag 0.4 on Windows using MSYS2 (mingw64),
REM then package a repo-committable ZIP + SHA256 manifest.
REM
REM Prereq: MSYS2 installed at C:\msys64 (see https://www.msys2.org/)
REM Usage (from repo root):
REM   grobid-home\scripts\build_pdfalto_win64_msys2.bat

set SCRIPT_DIR=%~dp0
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%build_pdfalto_win64_msys2.ps1"
if errorlevel 1 exit /b 1

endlocal



