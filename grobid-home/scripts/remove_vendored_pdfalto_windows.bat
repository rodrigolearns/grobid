@echo off
setlocal

REM Removes vendored Windows pdfalto binaries/DLLs from grobid-home/pdfalto/win-{64,32}/
REM Keeps xpdfrc and .gitkeep.
REM Usage:
REM   grobid-home\scripts\remove_vendored_pdfalto_windows.bat
REM   grobid-home\scripts\remove_vendored_pdfalto_windows.bat -DryRun

pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0remove_vendored_pdfalto_windows.ps1" %*
exit /b %ERRORLEVEL%


