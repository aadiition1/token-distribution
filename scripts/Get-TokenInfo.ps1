#Requires -Version 5.1
<#
.Synopsis
   Query ERC-20 token information
.DESCRIPTION
   Retrieves token metadata (name, symbol, decimals, total supply, balance)
   using Foundry's cast to call the contract on-chain.
   Requires Foundry (cast) to be installed: https://getfoundry.sh

.EXAMPLE
   .\Get-TokenInfo.ps1 -Token "0xabcd..." -RpcUrl "https://eth-mainnet.g.alchemy.com/v2/YOUR-KEY"

.EXAMPLE
   .\Get-TokenInfo.ps1 -Token "0xabcd..." -Account "0x1234..."
#>

param(
  [Parameter(Mandatory = $true)]
  [ValidatePattern('^0x[a-fA-F0-9]{40}$')]
  [string]$Token,

  [string]$Account,
  [string]$RpcUrl = $env:ETH_RPC_URL
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Prerequisite check ─────────────────────────────────────────────────────────

if (-not (Get-Command "cast" -ErrorAction SilentlyContinue)) {
  Write-Error "Foundry 'cast' not found. Install from https://getfoundry.sh and re-run."
  exit 1
}

if (-not $RpcUrl) {
  Write-Error "RpcUrl not provided and ETH_RPC_URL environment variable is not set."
  exit 1
}

$Token = $Token.ToLowerInvariant()
if ($Account) {
  $Account = $Account.ToLowerInvariant()
}

Write-Host ""
Write-Host "📋 Token Information" -ForegroundColor Cyan
Write-Host "Token Address: $Token" -ForegroundColor Green
Write-Host ""

# ── Helper: call a read-only contract function ────────────────────────────────
# Signature must include return type(s), e.g. "name()(string)" or
# "balanceOf(address)(uint256)".  cast decodes the return value automatically.
function Invoke-ContractRead {
  param(
    [string]$ContractAddress,
    [string]$Signature,          # full sig including return type, e.g. "decimals()(uint8)"
    [string[]]$CallArgs = @(),
    [string]$RpcUrl
  )

  $result = (& cast call $ContractAddress $Signature @CallArgs --rpc-url $RpcUrl 2>&1) -join "`n"
  return $result.Trim()
}

# ── Helper: format a raw uint256 token amount as human-readable ───────────────
function Format-TokenAmount {
  param([string]$RawAmount, [int]$Decimals)

  $divisor   = [System.Numerics.BigInteger]::Pow(10, $Decimals)
  $bigVal    = [System.Numerics.BigInteger]::Parse($RawAmount)
  $whole     = $bigVal / $divisor
  $remainder = $bigVal % $divisor

  $display = "$whole"
  if ($remainder -gt 0) {
    $fracStr  = $remainder.ToString().PadLeft($Decimals, '0').TrimEnd('0')
    $display += ".$fracStr"
  }
  return $display
}

# ── name() ────────────────────────────────────────────────────────────────────
Write-Host "Fetching name()..." -NoNewline -ForegroundColor DarkGray
$name = Invoke-ContractRead -ContractAddress $Token -Signature "name()(string)" -RpcUrl $RpcUrl
if ($LASTEXITCODE -eq 0) {
  Write-Host " ✅" -ForegroundColor Green
  Write-Host "  Name: $name" -ForegroundColor White
} else {
  Write-Host " ⚠️  (not available)" -ForegroundColor Yellow
  $name = $null
}

# ── symbol() ──────────────────────────────────────────────────────────────────
Write-Host "Fetching symbol()..." -NoNewline -ForegroundColor DarkGray
$symbol = Invoke-ContractRead -ContractAddress $Token -Signature "symbol()(string)" -RpcUrl $RpcUrl
if ($LASTEXITCODE -eq 0) {
  Write-Host " ✅" -ForegroundColor Green
  Write-Host "  Symbol: $symbol" -ForegroundColor White
} else {
  Write-Host " ⚠️  (not available)" -ForegroundColor Yellow
  $symbol = $null
}

# ── decimals() ────────────────────────────────────────────────────────────────
Write-Host "Fetching decimals()..." -NoNewline -ForegroundColor DarkGray
$decimalsRaw = Invoke-ContractRead -ContractAddress $Token -Signature "decimals()(uint8)" -RpcUrl $RpcUrl
if ($LASTEXITCODE -eq 0) {
  Write-Host " ✅" -ForegroundColor Green
  Write-Host "  Decimals: $decimalsRaw" -ForegroundColor White
  $decimalsInt = [int]$decimalsRaw
} else {
  Write-Host " ❌" -ForegroundColor Red
  Write-Error "Failed to fetch decimals — cannot continue without this value."
  exit 1
}

# ── totalSupply() ─────────────────────────────────────────────────────────────
Write-Host "Fetching totalSupply()..." -NoNewline -ForegroundColor DarkGray
$totalSupplyRaw = Invoke-ContractRead -ContractAddress $Token -Signature "totalSupply()(uint256)" -RpcUrl $RpcUrl
if ($LASTEXITCODE -eq 0) {
  Write-Host " ✅" -ForegroundColor Green

  try {
    $displayValue = Format-TokenAmount -RawAmount $totalSupplyRaw -Decimals $decimalsInt
    Write-Host "  Total Supply: $displayValue $symbol" -ForegroundColor White
    Write-Host "  Total Supply (raw): $totalSupplyRaw" -ForegroundColor DarkGray
  } catch {
    Write-Host "  Total Supply (raw): $totalSupplyRaw" -ForegroundColor White
  }
} else {
  Write-Host " ❌" -ForegroundColor Red
  Write-Error "Failed to fetch totalSupply."
  exit 1
}

# ── balanceOf(account) ────────────────────────────────────────────────────────
if ($Account) {
  Write-Host ""
  Write-Host "Fetching balanceOf($Account)..." -NoNewline -ForegroundColor DarkGray
  $balanceRaw = Invoke-ContractRead -ContractAddress $Token `
    -Signature "balanceOf(address)(uint256)" -CallArgs @($Account) -RpcUrl $RpcUrl
  if ($LASTEXITCODE -eq 0) {
    Write-Host " ✅" -ForegroundColor Green

    try {
      $displayValue = Format-TokenAmount -RawAmount $balanceRaw -Decimals $decimalsInt
      Write-Host "  Balance: $displayValue $symbol" -ForegroundColor White
      Write-Host "  Balance (raw): $balanceRaw" -ForegroundColor DarkGray
    } catch {
      Write-Host "  Balance (raw): $balanceRaw" -ForegroundColor White
    }
  } else {
    Write-Host " ❌" -ForegroundColor Red
    Write-Error "Failed to fetch balance for $Account."
    exit 1
  }
}

Write-Host ""
Write-Host "✅ Token information retrieved successfully" -ForegroundColor Green
