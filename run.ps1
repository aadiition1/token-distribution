#!/usr/bin/env pwsh
<#
.SYNOPSIS
    One-Shot Token Distribution - PowerShell Launcher
.DESCRIPTION
    Checks Node.js and dependencies, then launches the wizard.
    Run on Windows, macOS, or Linux.
.EXAMPLE
    .\run.ps1
    .\run.ps1 --dry-run
    .\run.ps1 --env .env.bsc
#>

param(
    [switch]$DryRun,
    [string]$Env = ".env"
)

$ErrorActionPreference = "Stop"

function Write-Banner {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Magenta
    Write-Host "║   🚀  TOKEN DISTRIBUTION WIZARD — PowerShell Launcher                       ║" -ForegroundColor Magenta
    Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Magenta
    Write-Host ""
}

Write-Banner

# Check Node.js
try {
    $nodeVersion = node --version 2>&1
    Write-Host "  ✅ Node.js: $nodeVersion" -ForegroundColor Green
} catch {
    Write-Host "  ❌ Node.js not found. Install from https://nodejs.org" -ForegroundColor Red
    exit 1
}

# Check node_modules
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$nodeModules = Join-Path $scriptDir "node_modules"

if (-not (Test-Path $nodeModules)) {
    Write-Host "  📦 Installing dependencies..." -ForegroundColor Yellow
    Push-Location $scriptDir
    npm install
    Pop-Location
}

# Build args
$args = @("wizard/run.js")
if ($DryRun) { $args += "--dry-run" }
if ($Env -ne ".env") { $args += @("--env", $Env) }

Write-Host "  🚀 Starting wizard..." -ForegroundColor Cyan
Write-Host ""

node @args
