@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0deploy_all.ps1" -PackageOnly
exit /b %errorlevel%
