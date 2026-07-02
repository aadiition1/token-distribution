@echo off
REM One-Shot Token Distribution - CMD Launcher
REM Usage: run.bat [--dry-run]

chcp 65001 >nul
echo.
echo ╔══════════════════════════════════════════════════════════════════════════════╗
echo ║   🚀  TOKEN DISTRIBUTION WIZARD — CMD Launcher                              ║
echo ╚══════════════════════════════════════════════════════════════════════════════╝
echo.

where node >nul 2>&1
if errorlevel 1 (
    echo   ❌ Node.js not found. Install from https://nodejs.org
    exit /b 1
)

for /f "tokens=*" %%i in ('node --version') do set NODE_VER=%%i
echo   ✅ Node.js: %NODE_VER%

if not exist "%~dp0node_modules" (
    echo   📦 Installing dependencies...
    cd /d "%~dp0"
    npm install
)

echo   🚀 Starting wizard...
echo.

node "%~dp0wizard\run.js" %*
