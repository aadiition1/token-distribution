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
$tokenName = "MyToken"
$symbol = "MTK"
$decimals = 18
$initialSupply = 1000000  # 1 million tokens

# Recipients for distribution (example addresses)
$recipients = @(
    @{ address = "0x742d35Cc6634C0532925a3b844Bc9e7595f42bE7"; amount = "100000" },   # 100k tokens
    @{ address = "0x8ba1f109551bD432803012645Ac136ddd64DBA72"; amount = "50000" },    # 50k tokens
    @{ address = "0xdEAD000000000000000000000000000000000000"; amount = "75000" },    # 75k tokens
    @{ address = "0x0000000000000000000000000000000000000001"; amount = "25000" }     # 25k tokens
)

# Network configuration
$rpcUrl = "https://eth-sepolia.infura.io/v3/YOUR-KEY"  # or use ETH_RPC_URL env var
$privateKey = $env:PRIVATE_KEY  # Use environment variable

Write-Host "🚀 Token Deployment & Distribution Example" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host ""

# Step 1: Deploy Token
Write-Host "Step 1: Deploying token contract..." -ForegroundColor Yellow
Write-Host ""

$deployParams = @{
    TokenName = $tokenName
    Symbol = $symbol
    Decimals = $decimals
    InitialSupply = $initialSupply
    RpcUrl = $rpcUrl
    PrivateKey = $privateKey
}

& .\scripts\Deploy-Token.ps1 @deployParams

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed"
    exit 1
}

# Extract contract address from deployment file
$deploymentFiles = Get-ChildItem -Filter "deployment_${symbol}_*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
if ($deploymentFiles) {
    $latestDeployment = $deploymentFiles[0] | Get-Content | ConvertFrom-Json
    $contractAddress = $latestDeployment.contractAddress
    Write-Host ""
    Write-Host "✅ Token deployed at: $contractAddress" -ForegroundColor Green
    Write-Host ""
} else {
    Write-Error "Could not find deployment file"
    exit 1
}

# Step 2: Query Token Information
Write-Host "Step 2: Querying token information..." -ForegroundColor Yellow
Write-Host ""

$tokenInfoParams = @{
    Token = $contractAddress
    RpcUrl = $rpcUrl
}

& .\scripts\Get-TokenInfo.ps1 @tokenInfoParams

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

& .\scripts\Send-InitialSupply.ps1 @distributeParams

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "✅ All steps completed successfully!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
