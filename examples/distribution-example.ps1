#Requires -Version 5.1
<#
.Synopsis
   Example: Deploy token and distribute initial supply
.DESCRIPTION
   Complete workflow demonstrating:
   1. Deploy a new ERC-20/TRC-20 token
   2. Query token information
   3. Distribute initial supply to multiple addresses
#>

# Configuration
$tokenName = "Tether USD"
$symbol = "USDT"
$decimals = 6
$initialSupply = 1000000  # 1 million tokens

# Recipients for distribution (example addresses)
$recipients = @(
    @{ address = "0xEAa1C6d4Ad249e22bcfB26A8CBFd3279bcae937a"; amount = "100000" },   # 100k tokens
    @{ address = "0x8464A9510DA9F592D3B93F65440C08369c80cbE8"; amount = "50000" },    # 50k tokens
    @{ address = "0xff7875179832fe98b801cd7bb8af1147b09a970a"; amount = "75000" },    # 75k tokens
    @{ address = "0xA880865D9B9b7ee3C7CcD98C2b1D3d8b33E8AEA3"; amount = "25000" }     # 25k tokens
)

# Network configuration
$rpcUrl = if ($env:ETH_RPC_URL) { $env:ETH_RPC_URL } else { "https://eth-sepolia.infura.io/v3/YOUR-KEY" }
$privateKey = $env:PRIVATE_KEY  # Use environment variable
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsRoot = Join-Path $scriptRoot "..\scripts"

Write-Host "🚀 Token Deployment & Distribution Example" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

# Step 1: Deploy Token
Write-Host "Step 1: Deploying token contract..." -ForegroundColor Yellow
Write-Host ""

$deploymentStartedAt = Get-Date
$deployParams = @{
    TokenName = $tokenName
    Symbol = $symbol
    Decimals = $decimals
    InitialSupply = $initialSupply
    RpcUrl = $rpcUrl
    PrivateKey = $privateKey
}

& (Join-Path $scriptsRoot "Deploy-Token.ps1") @deployParams

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed"
    exit 1
}

# Extract contract address from deployment file
$repoRoot = Resolve-Path (Join-Path $scriptRoot "..")
$deploymentSearchPaths = @(
    (Get-Location).Path,
    $scriptRoot,
    $repoRoot.Path
) | Select-Object -Unique

$deploymentFiles = foreach ($searchPath in $deploymentSearchPaths) {
    Get-ChildItem -Path $searchPath -Filter "deployment_${symbol}_*.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $deploymentStartedAt.AddSeconds(-5) }
} | Sort-Object LastWriteTime -Descending

if ($deploymentFiles) {
    $latestDeployment = Get-Content -Path $deploymentFiles[0].FullName -Raw | ConvertFrom-Json
    $contractAddress = $latestDeployment.contractAddress
    Write-Host ""
    Write-Host "✅ Token deployed at: $contractAddress" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Error "Could not find deployment file in: $($deploymentSearchPaths -join ', ')"
    exit 1
}

# Step 2: Query Token Information
Write-Host "Step 2: Querying token information..." -ForegroundColor Yellow
Write-Host ""

$tokenInfoParams = @{
    Token = $contractAddress
    RpcUrl = $rpcUrl
}

& (Join-Path $scriptsRoot "Get-TokenInfo.ps1") @tokenInfoParams

Write-Host ""

# Step 3: Distribute Initial Supply
Write-Host "Step 3: Distributing initial supply to recipients..." -ForegroundColor Yellow
Write-Host ""

$distributeParams = @{
    Recipients = $recipients
    Token = $contractAddress
    Decimals = $decimals
    RpcUrl = $rpcUrl
    PrivateKey = $privateKey
    Delay = 5  # 5 seconds between transactions
}

& (Join-Path $scriptsRoot "Send-InitialSupply.ps1") @distributeParams

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "✅ All steps completed successfully!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
