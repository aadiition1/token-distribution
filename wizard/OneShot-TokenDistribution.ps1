#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.Synopsis
   One-shot interactive wizard: deploy a token and/or distribute it to recipients.
.DESCRIPTION
   Guides the operator through the full workflow:
     1. Prerequisites check (Foundry cast + forge)
     2. RPC URL and private key collection
     3. Optional token deployment (forge create) OR existing token address
     4. Recipients from CSV file or interactive input
     5. Distribution plan review + explicit confirmation
     6. Real on-chain execution via Send-InitialSupply.ps1
     7. Summary of confirmed transactions

   IMPORTANT: This wizard submits REAL transactions to the network you specify.
   No transaction is sent until you confirm the final prompt.

   Prerequisites:
     - Foundry (forge + cast): https://getfoundry.sh
     - A funded wallet (private key or PRIVATE_KEY env var)
     - An EVM-compatible RPC endpoint (or ETH_RPC_URL env var)

   Recipient CSV format (UTF-8, header row required):
     address,amount
     0xABC...,1000
     0xDEF...,500

.EXAMPLE
   ./wizard/OneShot-TokenDistribution.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Locate sibling scripts ─────────────────────────────────────────────────────
$ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot     = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$DeployScript = Join-Path $RepoRoot "scripts" "Deploy-Token.ps1"
$SendScript   = Join-Path $RepoRoot "scripts" "Send-InitialSupply.ps1"
$InfoScript   = Join-Path $RepoRoot "scripts" "Get-TokenInfo.ps1"

foreach ($s in @($DeployScript, $SendScript, $InfoScript)) {
  if (-not (Test-Path $s)) {
    Write-Error "Required script not found: $s`nMake sure you are running from the repository root or wizard/ directory."
    exit 1
  }
}

# ── Banner ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "┌─────────────────────────────────────────┐" -ForegroundColor Magenta
Write-Host "│  🚀  TOKEN DEPLOYMENT & DISTRIBUTION     │" -ForegroundColor Magenta
Write-Host "│       One-Shot Wizard  (Real Execution)  │" -ForegroundColor Magenta
Write-Host "└─────────────────────────────────────────┘" -ForegroundColor Magenta
Write-Host ""
Write-Host "⚠️  This wizard will send REAL on-chain transactions." -ForegroundColor Yellow
Write-Host "   You will be asked to confirm before anything is submitted." -ForegroundColor Yellow
Write-Host ""

# ── Prerequisites ──────────────────────────────────────────────────────────────
Write-Host "🔍 Checking prerequisites..." -ForegroundColor Cyan

$missingTools = @()
foreach ($tool in @("cast", "forge")) {
  if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
    $missingTools += $tool
  }
}

if ($missingTools.Count -gt 0) {
  Write-Host ""
  Write-Error "Missing required tools: $($missingTools -join ', ')`nInstall Foundry from https://getfoundry.sh and re-run."
  exit 1
}

$castVersion  = (& cast --version 2>&1) | Select-Object -First 1
$forgeVersion = (& forge --version 2>&1) | Select-Object -First 1
Write-Host "  ✅ cast  : $castVersion" -ForegroundColor Green
Write-Host "  ✅ forge : $forgeVersion" -ForegroundColor Green
Write-Host ""

# ── Helper: prompt with optional default ──────────────────────────────────────
function Read-Input {
  param(
    [string]$Prompt,
    [string]$Default = "",
    [switch]$Secret
  )

  $displayDefault = if ($Default) { " [$Default]" } else { "" }
  Write-Host "${Prompt}${displayDefault}: " -NoNewline -ForegroundColor Cyan

  if ($Secret) {
    $secStr = Read-Host -AsSecureString
    $bstr   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secStr)
    $plain  = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    $value  = $plain
  } else {
    $value = Read-Host
  }

  if ([string]::IsNullOrWhiteSpace($value) -and $Default) {
    return $Default
  }
  return $value
}

# ── Step 1: RPC URL ────────────────────────────────────────────────────────────
Write-Host "STEP 1 — Network" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────" -ForegroundColor DarkGray

$rpcUrl = $env:ETH_RPC_URL
if ($rpcUrl) {
  Write-Host "  Using RPC URL from ETH_RPC_URL: $rpcUrl" -ForegroundColor Green
} else {
  $rpcUrl = Read-Input -Prompt "RPC URL (e.g. https://eth-sepolia.infura.io/v3/YOUR-KEY)"
}

if ([string]::IsNullOrWhiteSpace($rpcUrl)) {
  Write-Error "RPC URL is required."
  exit 1
}

Write-Host ""

# ── Step 2: Private key ────────────────────────────────────────────────────────
Write-Host "STEP 2 — Wallet" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Tip: set the PRIVATE_KEY environment variable to avoid typing it each time." -ForegroundColor DarkGray

$privateKey = $env:PRIVATE_KEY
if ($privateKey) {
  Write-Host "  Using private key from PRIVATE_KEY env var." -ForegroundColor Green
} else {
  $privateKey = Read-Input -Prompt "Private key (0x-prefixed)" -Secret
}

if ([string]::IsNullOrWhiteSpace($privateKey)) {
  Write-Error "Private key is required."
  exit 1
}

# Verify the key works and derive the deployer address
Write-Host "  Verifying key..." -NoNewline -ForegroundColor DarkGray
$walletAddress = (& cast wallet address --private-key $privateKey 2>&1)
if ($LASTEXITCODE -ne 0) {
  Write-Host " ❌" -ForegroundColor Red
  Write-Error "Failed to derive wallet address. Check that the private key is valid (0x-prefixed hex)."
  exit 1
}
$walletAddress = $walletAddress.Trim()
Write-Host " ✅  $walletAddress" -ForegroundColor Green
Write-Host ""

# ── Step 3: Token ──────────────────────────────────────────────────────────────
Write-Host "STEP 3 — Token" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  (D) Deploy a new ERC-20 token" -ForegroundColor White
Write-Host "  (E) Use an existing deployed token address" -ForegroundColor White

$tokenChoice = ""
while ($tokenChoice -notin @("D", "E")) {
  $tokenChoice = (Read-Input -Prompt "Choice [D/E]").Trim().ToUpper()
  if ($tokenChoice -notin @("D", "E")) {
    Write-Host "  Please enter D or E." -ForegroundColor Yellow
  }
}

$tokenAddress = $null
$tokenDecimals = 18

if ($tokenChoice -eq "D") {
  # Deploy a new token
  Write-Host ""
  Write-Host "  — New token parameters —" -ForegroundColor DarkGray

  $tokenName     = Read-Input -Prompt "Token name (e.g. My Token)"
  $tokenSymbol   = Read-Input -Prompt "Token symbol (e.g. MTK)"
  $tokenDecimals = [int](Read-Input -Prompt "Decimals" -Default "18")
  $initialSupply = Read-Input -Prompt "Initial supply (whole tokens, e.g. 1000000)"

  # Validate inputs
  if ([string]::IsNullOrWhiteSpace($tokenName)) {
    Write-Error "Token name is required."
    exit 1
  }
  if ([string]::IsNullOrWhiteSpace($tokenSymbol)) {
    Write-Error "Token symbol is required."
    exit 1
  }
  if ($initialSupply -notmatch '^\d+$') {
    Write-Error "Initial supply must be a positive integer. Got: '$initialSupply'"
    exit 1
  }

  Write-Host ""
  Write-Host "  Deployment plan:" -ForegroundColor Yellow
  Write-Host "    Name          : $tokenName" -ForegroundColor White
  Write-Host "    Symbol        : $tokenSymbol" -ForegroundColor White
  Write-Host "    Decimals      : $tokenDecimals" -ForegroundColor White
  Write-Host "    Initial Supply: $initialSupply (whole tokens)" -ForegroundColor White
  Write-Host "    Deployer      : $walletAddress" -ForegroundColor White
  Write-Host ""

  $confirm = Read-Input -Prompt "Deploy now? [y/N]" -Default "N"
  if ($confirm.Trim().ToUpper() -ne "Y") {
    Write-Host "Deployment cancelled." -ForegroundColor Yellow
    exit 0
  }

  Write-Host ""
  Write-Host "📡 Deploying token..." -ForegroundColor Cyan

  # Change to repo root so Deploy-Token.ps1 can find contracts/
  Push-Location $RepoRoot
  try {
    & $DeployScript `
      -TokenName     $tokenName `
      -Symbol        $tokenSymbol `
      -Decimals      $tokenDecimals `
      -InitialSupply $initialSupply `
      -RpcUrl        $rpcUrl `
      -PrivateKey    $privateKey
  } finally {
    Pop-Location
  }

  if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed (exit code $LASTEXITCODE). Aborting distribution."
    exit 1
  }

  # Read the contract address from the deployment file written by Deploy-Token.ps1
  $deployFiles = Get-ChildItem -Path $RepoRoot -Filter "deployment_${tokenSymbol}_*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending
  if (-not $deployFiles) {
    Write-Error "Deployment succeeded but no deployment_${tokenSymbol}_*.json file found in $RepoRoot."
    exit 1
  }

  $deployInfo    = Get-Content $deployFiles[0].FullName -Raw | ConvertFrom-Json
  $tokenAddress  = $deployInfo.contractAddress
  $tokenDecimals = $deployInfo.decimals

  if (-not ($tokenAddress -match '^0x[a-fA-F0-9]{40}$')) {
    Write-Error "Deployment file missing a valid contractAddress. Got: '$tokenAddress'"
    exit 1
  }

  Write-Host ""
  Write-Host "✅ Token deployed at: $tokenAddress" -ForegroundColor Green

} else {
  # Use existing token
  Write-Host ""
  $tokenAddress = Read-Input -Prompt "Token contract address (0x-prefixed)"

  if ($tokenAddress -notmatch '^0x[a-fA-F0-9]{40}$') {
    Write-Error "Not a valid EVM address: '$tokenAddress'"
    exit 1
  }

  Write-Host "  Fetching token info..." -ForegroundColor DarkGray
  & $InfoScript -Token $tokenAddress -RpcUrl $rpcUrl 2>&1 | ForEach-Object {
    # Capture decimals from the info output so we don't need to re-ask
    if ($_ -match '^\s+Decimals:\s+(\d+)') {
      $tokenDecimals = [int]$Matches[1]
    }
    Write-Host "  $_"
  }

  if ($LASTEXITCODE -ne 0) {
    Write-Host "  ⚠️  Could not fetch token info automatically." -ForegroundColor Yellow
    $tokenDecimals = [int](Read-Input -Prompt "Enter token decimals manually" -Default "18")
  }
}

Write-Host ""

# ── Step 4: Recipients ─────────────────────────────────────────────────────────
Write-Host "STEP 4 — Recipients" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  (F) Load from CSV file (address,amount)" -ForegroundColor White
Write-Host "  (M) Enter recipients manually" -ForegroundColor White

$recipientChoice = ""
while ($recipientChoice -notin @("F", "M")) {
  $recipientChoice = (Read-Input -Prompt "Choice [F/M]").Trim().ToUpper()
  if ($recipientChoice -notin @("F", "M")) {
    Write-Host "  Please enter F or M." -ForegroundColor Yellow
  }
}

$recipients = @()

if ($recipientChoice -eq "F") {
  Write-Host ""
  $csvPath = Read-Input -Prompt "Path to recipients CSV file"
  $csvPath = $csvPath.Trim().Trim('"')

  # Resolve relative to CWD
  if (-not [System.IO.Path]::IsPathRooted($csvPath)) {
    $csvPath = Join-Path (Get-Location) $csvPath
  }

  if (-not (Test-Path $csvPath)) {
    Write-Error "File not found: $csvPath"
    exit 1
  }

  $csvRows = Import-Csv -Path $csvPath -Encoding UTF8
  if (-not $csvRows -or $csvRows.Count -eq 0) {
    Write-Error "CSV file is empty or has no data rows: $csvPath"
    exit 1
  }

  # Validate required columns
  $firstRow = $csvRows[0]
  if (-not ($firstRow.PSObject.Properties.Name -contains "address") -or
      -not ($firstRow.PSObject.Properties.Name -contains "amount")) {
    Write-Error "CSV must have 'address' and 'amount' columns. Found: $($firstRow.PSObject.Properties.Name -join ', ')"
    exit 1
  }

  foreach ($row in $csvRows) {
    $addr   = $row.address.Trim()
    $amount = "$($row.amount)".Trim()

    if ([string]::IsNullOrWhiteSpace($addr) -or [string]::IsNullOrWhiteSpace($amount)) {
      Write-Host "  ⚠️  Skipping row with empty address or amount: address='$addr' amount='$amount'" -ForegroundColor Yellow
      continue
    }

    if ($addr -notmatch '^0x[a-fA-F0-9]{40}$') {
      Write-Host "  ⚠️  Skipping invalid address: $addr" -ForegroundColor Yellow
      continue
    }

    $recipients += [PSCustomObject]@{ address = $addr; amount = $amount }
  }

  if ($recipients.Count -eq 0) {
    Write-Error "No valid recipients found in CSV file."
    exit 1
  }

  Write-Host "  ✅ Loaded $($recipients.Count) recipients from $csvPath" -ForegroundColor Green

} else {
  # Manual input
  Write-Host ""
  Write-Host "  Enter recipients one at a time (leave address blank when done)." -ForegroundColor DarkGray
  $index = 1
  while ($true) {
    $addr = (Read-Input -Prompt "  [$index] Address (blank to finish)").Trim()
    if ([string]::IsNullOrWhiteSpace($addr)) { break }

    if ($addr -notmatch '^0x[a-fA-F0-9]{40}$') {
      Write-Host "  ⚠️  Invalid address format — must be 0x followed by 40 hex chars. Try again." -ForegroundColor Yellow
      continue
    }

    $amount = (Read-Input -Prompt "  [$index] Amount (tokens)").Trim()
    if ([string]::IsNullOrWhiteSpace($amount)) {
      Write-Host "  ⚠️  Amount cannot be empty. Try again." -ForegroundColor Yellow
      continue
    }

    $recipients += [PSCustomObject]@{ address = $addr; amount = $amount }
    $index++
  }

  if ($recipients.Count -eq 0) {
    Write-Host "No recipients entered. Nothing to distribute." -ForegroundColor Yellow
    exit 0
  }
}

Write-Host ""

# ── Step 5: Optional delay ─────────────────────────────────────────────────────
$txDelay = [int](Read-Input -Prompt "Seconds to wait between transactions (0 = no delay)" -Default "2")
Write-Host ""

# ── Step 6: Review and confirm ─────────────────────────────────────────────────
Write-Host "STEP 6 — Review Distribution Plan" -ForegroundColor Magenta
Write-Host "─────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Token contract : $tokenAddress" -ForegroundColor White
Write-Host "  Decimals       : $tokenDecimals" -ForegroundColor White
Write-Host "  Sender wallet  : $walletAddress" -ForegroundColor White
Write-Host "  Network RPC    : $rpcUrl" -ForegroundColor White
Write-Host "  Tx delay       : $txDelay second(s)" -ForegroundColor White
Write-Host ""
Write-Host "  Recipients ($($recipients.Count)):" -ForegroundColor White

$totalTokens = [System.Numerics.BigInteger]::Zero
foreach ($r in $recipients) {
  Write-Host ("    {0,-44} {1}" -f $r.address, "$($r.amount) tokens") -ForegroundColor DarkGray
  try {
    $totalTokens += [System.Numerics.BigInteger]::Parse($r.amount -replace '\..*', '')
  } catch {}
}

Write-Host ""
Write-Host "  Approximate total: $totalTokens tokens (whole-unit sum)" -ForegroundColor Yellow
Write-Host ""
Write-Host "⚠️  FINAL WARNING: The above transactions will be submitted to the REAL network." -ForegroundColor Red
Write-Host "   There is NO undo once a transaction is sent." -ForegroundColor Red
Write-Host ""

$finalConfirm = Read-Input -Prompt "Type 'YES' to proceed with real distribution (anything else aborts)" -Default "no"
if ($finalConfirm.Trim() -ne "YES") {
  Write-Host ""
  Write-Host "Aborted by operator. No transactions were sent." -ForegroundColor Yellow
  exit 0
}

Write-Host ""
Write-Host "🚀 Starting distribution..." -ForegroundColor Cyan
Write-Host ""

# ── Step 7: Execute distribution ──────────────────────────────────────────────

Push-Location $RepoRoot
try {
  & $SendScript `
    -Recipients $recipients `
    -Token      $tokenAddress `
    -Decimals   "$tokenDecimals" `
    -RpcUrl     $rpcUrl `
    -PrivateKey $privateKey `
    -Delay      $txDelay
} finally {
  Pop-Location
}

$distExitCode = $LASTEXITCODE

Write-Host ""
if ($distExitCode -eq 0) {
  Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
  Write-Host "✅ Distribution complete — all transactions confirmed on-chain." -ForegroundColor Green
  Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
} else {
  Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
  Write-Host "⚠️  Distribution finished with failures." -ForegroundColor Red
  Write-Host "   Check the distribution_results_*.json file for details." -ForegroundColor Yellow
  Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
}

exit $distExitCode
