@echo off
:: Aras Easy Installer -- launcher that bypasses execution policy and self-elevates to admin.

:: Check for admin rights
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

:: Run the PowerShell installer with execution policy bypass
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-Aras.ps1"
pause
