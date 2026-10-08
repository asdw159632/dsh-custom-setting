@echo off
rem Push this workspace to GitHub.
rem
rem Why this wrapper exists:
rem   * DSH sandbox blocks git's credential.helper/askpass (MSYS sh cannot create
rem     a signal pipe), so plain `git push` always fails here.
rem   * Only Windows PowerShell 5.1 is installed (no pwsh), and its default
rem     execution policy may block .ps1 files, hence -ExecutionPolicy Bypass.
rem
rem Usage:  scripts\push.cmd [branch] [remote]
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0push.ps1" %*
exit /b %ERRORLEVEL%
