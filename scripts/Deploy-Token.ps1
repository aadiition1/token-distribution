#Requires -Version 5.1
<#
.Synopsis
   Deploy an ERC-20 token contract using Foundry (forge create)
.DESCRIPTION
   Compiles and deploys a new ERC-20 token contract to an EVM network.
   Requires Foundry (forge + cast) to be installed: https://getfoundry.sh

   The script blocks until the deployment transaction is confirmed on-chain and
   verifies the receipt status before reporting success.

.EXAMPLE
   .\Deploy-Token.ps1 -TokenName "My Token" -Symbol "MTK" -Decimals 18 `
     -InitialSupply 1000000 -RpcUrl "https://eth-sepolia.infura.io/v3/YOUR-KEY"

.EXAMPLE
   $env:ETH_RPC_URL = "https://mainnet.infura.io/v3/YOUR-KEY"
   $env:PRIVATE_KEY  = "0xYOUR_KEY"
   .\Deploy-Token.ps1 -TokenName "MyToken" -Symbol "MTK" -Decimals 18 -InitialSupply 1000000
#>

param(
  [Parameter(Mandatory = $true)]
  [string]$TokenName,

  [Parameter(Mandatory = $true)]
  [string]$Symbol,

  # 0-255 — mapped to Solidity uint8
  [Parameter(Mandatory = $true)]
  [ValidateRange(0, 255)]
  [int]$Decimals,

  # Whole-token initial supply (constructor multiplies by 10^decimals internally)
  [Parameter(Mandatory = $true)]
  [string]$InitialSupply,

  [string]$ContractName = "ERC20Token",
  [string]$ContractPath = "./contracts/ERC20Token.sol",
  [string]$RpcUrl      = $env:ETH_RPC_URL,
  [string]$PrivateKey  = $env:PRIVATE_KEY,
  [switch]$Verify,
  [string]$VerifyUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Prerequisite checks ────────────────────────────────────────────────────────

if (-not (Get-Command "forge" -ErrorAction SilentlyContinue)) {
  Write-Error "Foundry 'forge' not found. Install from https://getfoundry.sh and re-run."
  exit 1
}

if (-not (Get-Command "cast" -ErrorAction SilentlyContinue)) {
  Write-Error "Foundry 'cast' not found. Install from https://getfoundry.sh and re-run."
  exit 1
}

# ── Input validation ───────────────────────────────────────────────────────────

if (-not $RpcUrl) {
  Write-Error "RpcUrl not provided and ETH_RPC_URL environment variable is not set."
  exit 1
}

if (-not $PrivateKey) {
  Write-Error "PrivateKey not provided and PRIVATE_KEY environment variable is not set."
  exit 1
}

# Validate InitialSupply is a non-negative integer string
if ($InitialSupply -notmatch '^\d+$') {
  Write-Error "InitialSupply must be a non-negative integer (whole tokens). Got: '$InitialSupply'"
  exit 1
}

# Resolve contract path (try CWD first, then relative to this script's directory)
if (-not [System.IO.Path]::IsPathRooted($ContractPath)) {
  $cwdResolved = Join-Path (Get-Location) $ContractPath
  if (Test-Path $cwdResolved) {
    $ContractPath = $cwdResolved
  } else {
    # Script is in scripts/, contract is in contracts/ at the same level
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $repoRoot  = Split-Path -Parent $scriptDir
    $repoResolved = Join-Path $repoRoot "contracts" "ERC20Token.sol"
    if (Test-Path $repoResolved) {
      $ContractPath = $repoResolved
    }
  }
}

if (-not (Test-Path $ContractPath)) {
  Write-Error "Contract file not found: $ContractPath"
  exit 1
}

# ── Derive deployer address ────────────────────────────────────────────────────

$deployer = (& cast wallet address --private-key $PrivateKey 2>&1)
if ($LASTEXITCODE -ne 0) {
  Write-Error "Failed to derive address from private key: $deployer"
  exit 1
}
$deployer = $deployer.Trim()

# ── Print deployment plan ──────────────────────────────────────────────────────

Write-Host ""
Write-Host "🚀 Token Contract Deployment" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Token Name    : $TokenName" -ForegroundColor Green
Write-Host "Symbol        : $Symbol" -ForegroundColor Green
Write-Host "Decimals      : $Decimals" -ForegroundColor Green
Write-Host "Initial Supply: $InitialSupply (whole tokens)" -ForegroundColor Green
Write-Host ""
Write-Host "Deployer  : $deployer" -ForegroundColor Yellow
Write-Host "RPC URL   : $RpcUrl" -ForegroundColor DarkGray
Write-Host "Contract  : $ContractPath" -ForegroundColor DarkGray
Write-Host ""

# ── Compile and deploy via forge create ───────────────────────────────────────

Write-Host "📡 Compiling and deploying with forge create..." -ForegroundColor Cyan

$forgeArgs = @(
  "create",
  "${ContractPath}:${ContractName}",
  "--constructor-args", $TokenName, $Symbol, "$Decimals", "$InitialSupply",
  "--rpc-url",    $RpcUrl,
  "--private-key", $PrivateKey,
  "--json"
)

# Capture stdout (JSON) and discard compiler progress on stderr
$forgeOutput = & forge @forgeArgs 2>$null
$forgeExitCode = $LASTEXITCODE

if ($forgeExitCode -ne 0) {
  # Re-run without --json to surface the real error message
  $forgeErr = & forge @($forgeArgs | Where-Object { $_ -ne "--json" }) 2>&1
  Write-Error "forge create failed (exit $forgeExitCode):`n$($forgeErr -join "`n")"
  exit 1
}

# forge create --json writes one JSON object to stdout
$jsonText = ($forgeOutput -join "").Trim()
if (-not $jsonText) {
  Write-Error "forge create returned no output. Deployment status unknown — do NOT assume success."
  exit 1
}

try {
  $deployResult = $jsonText | ConvertFrom-Json
} catch {
  Write-Error "Failed to parse forge create JSON output: $jsonText"
  exit 1
}

$txHash        = $deployResult.transactionHash
$contractAddress = $deployResult.deployedTo

if (-not $txHash -or $txHash -notmatch '^0x[a-fA-F0-9]{64}$') {
  Write-Error "forge create output missing a valid transactionHash. Output: $jsonText"
  exit 1
}

if (-not $contractAddress -or $contractAddress -notmatch '^0x[a-fA-F0-9]{40}$') {
  Write-Error "forge create output missing a valid deployedTo address. Output: $jsonText"
  exit 1
}

Write-Host "✅ Deployment transaction confirmed" -ForegroundColor Green
Write-Host "   TxHash          : $txHash" -ForegroundColor Yellow
Write-Host "   Contract Address: $contractAddress" -ForegroundColor Green

# ── Verify receipt status on-chain ────────────────────────────────────────────

Write-Host ""
Write-Host "⏳ Fetching transaction receipt to verify success..." -ForegroundColor Cyan

$receiptRaw = (& cast receipt $txHash --rpc-url $RpcUrl --json 2>&1) -join ""
if ($LASTEXITCODE -ne 0) {
  Write-Error "cast receipt failed: $receiptRaw"
  exit 1
}

try {
  $receipt = $receiptRaw | ConvertFrom-Json
} catch {
  Write-Error "Failed to parse receipt JSON: $receiptRaw"
  exit 1
}

# Status is "0x1" for success (hex string from cast), "0x0" for revert.
# Normalize to integer before comparing.
$statusInt = if ($receipt.status -is [string] -and $receipt.status.StartsWith("0x")) {
  [Convert]::ToInt32($receipt.status, 16)
} else {
  [int]$receipt.status
}
if ($statusInt -ne 1) {
  Write-Error "Deployment transaction REVERTED on-chain (status=$($receipt.status)). Contract was NOT deployed."
  exit 1
}

Write-Host "✅ On-chain status: SUCCESS" -ForegroundColor Green
Write-Host "   Block Number: $(& cast --to-dec $receipt.blockNumber 2>$null)" -ForegroundColor DarkGray
Write-Host "   Gas Used    : $(& cast --to-dec $receipt.gasUsed 2>$null)" -ForegroundColor DarkGray

# ── Save deployment info ───────────────────────────────────────────────────────

$deploymentInfo = [ordered]@{
  timestamp       = Get-Date -Format "o"
  network         = $RpcUrl
  deployer        = $deployer
  contractAddress = $contractAddress
  contractName    = $ContractName
  tokenName       = $TokenName
  symbol          = $Symbol
  decimals        = $Decimals
  initialSupply   = $InitialSupply
  transactionHash = $txHash
} | ConvertTo-Json -Depth 10

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$deploymentFile = "deployment_${Symbol}_${ts}.json"
$deploymentInfo | Out-File -FilePath $deploymentFile -Encoding UTF8

Write-Host ""
Write-Host "💾 Deployment info saved to: $deploymentFile" -ForegroundColor Yellow

# ── Optional block-explorer hint ──────────────────────────────────────────────

if ($Verify -and $VerifyUrl) {
  Write-Host ""
  Write-Host "🔍 View on explorer: $VerifyUrl/address/$contractAddress" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "✅ Deployment Complete!" -ForegroundColor Green
Write-Host "   Contract: $contractAddress" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

exit 0
