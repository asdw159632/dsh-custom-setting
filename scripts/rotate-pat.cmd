@echo off
rem Rotate the GitHub PAT used by git/Windows Credential Manager.
rem Runs rotate-pat.ps1 with hidden token input (Windows PowerShell 5.1 has no pwsh here).
rem
rem Usage:  scripts\rotate-pat.cmd [ -CheckOnly ]
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0rotate-pat.ps1" %*
exit /b %ERRORLEVEL%
