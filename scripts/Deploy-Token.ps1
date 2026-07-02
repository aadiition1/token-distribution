#Requires -Version 5.1
<#
.Synopsis
   Deploy an ERC-20/TRC-20 token contract
.DESCRIPTION
   Deploys a new token contract to Ethereum or TRON networks.
   Requires the Solidity contract file to be compiled (via forge or solc).
   
.EXAMPLE
   .\Deploy-Token.ps1 -ContractName "TestToken" -TokenName "My Token" -Symbol "MTK" `
     -Decimals 18 -InitialSupply 1000000 -RpcUrl "https://eth-sepolia.infura.io/v3/YOUR-KEY"

.EXAMPLE
   .\Deploy-Token.ps1 -ContractPath "./ERC20Token.sol" -Constructor "Tether USD","USDT",18,1000000
#>

param(
  [Parameter(Mandatory = $true)]
  [string]$TokenName,

  [Parameter(Mandatory = $true)]
  [string]$Symbol,

  [Parameter(Mandatory = $true)]
  [uint8]$Decimals,

  [Parameter(Mandatory = $true)]
  [uint256]$InitialSupply,

  [string]$ContractName = "ERC20Token",
  [string]$ContractPath = "./contracts/ERC20Token.sol",
  [string]$RpcUrl = $env:ETH_RPC_URL,
  [string]$PrivateKey = $env:PRIVATE_KEY,
  [switch]$Verify,
  [string]$VerifyUrl
)

# Validation
if (-not $RpcUrl) {
  Write-Error "RpcUrl not provided and ETH_RPC_URL environment variable not set"
  exit 1
}

if (-not $PrivateKey) {
  Write-Error "PrivateKey not provided and PRIVATE_KEY environment variable not set"
  exit 1
}

if (-not (Test-Path $ContractPath)) {
  Write-Error "Contract file not found: $ContractPath"
  exit 1
}

# Get deployer address
$deployer = & cast wallet address --private-key $PrivateKey 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Error "Failed to derive address from private key"
  exit 1
}

Write-Host "🚀 Token Contract Deployment" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Token Name: $TokenName" -ForegroundColor Green
Write-Host "Symbol: $Symbol" -ForegroundColor Green
Write-Host "Decimals: $Decimals" -ForegroundColor Green
Write-Host "Initial Supply: $InitialSupply" -ForegroundColor Green
Write-Host ""
Write-Host "Deployer: $deployer" -ForegroundColor Yellow
Write-Host "RPC URL: $RpcUrl" -ForegroundColor DarkGray
Write-Host ""

# Read contract bytecode
Write-Host "Reading contract from: $ContractPath" -ForegroundColor DarkGray
$contractContent = Get-Content -Path $ContractPath -Raw

# Check if using forge or solc
$forgeProject = Test-Path "forge.toml" -ErrorAction SilentlyContinue
$hardhatProject = Test-Path "hardhat.config.js" -ErrorAction SilentlyContinue

if ($forgeProject) {
  Write-Host "📦 Using Foundry (forge) to compile..." -ForegroundColor Cyan
  
  # Build with forge
  forge build 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Error "Forge compilation failed"
    exit 1
  }
  
  # Get compiled artifact
  $artifactPath = "./out/$ContractName.sol/$ContractName.json"
  if (-not (Test-Path $artifactPath)) {
    Write-Error "Compiled artifact not found: $artifactPath"
    exit 1
  }
  
  $artifact = Get-Content $artifactPath | ConvertFrom-Json
  $bytecode = $artifact.bytecode.object
  $abi = $artifact.abi | ConvertTo-Json -Compress
  
} elseif ($hardhatProject) {
  Write-Host "📦 Using Hardhat to compile..." -ForegroundColor Cyan
  
  # Build with hardhat
  npx hardhat compile 2>&1 | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Write-Error "Hardhat compilation failed"
    exit 1
  }
  
  # Get compiled artifact
  $artifactPath = "./artifacts/contracts/$([System.IO.Path]::GetFileName($ContractPath))/$ContractName.json"
  if (-not (Test-Path $artifactPath)) {
    Write-Error "Compiled artifact not found: $artifactPath"
    exit 1
  }
  
  $artifact = Get-Content $artifactPath | ConvertFrom-Json
  $bytecode = $artifact.bytecode
  $abi = $artifact.abi | ConvertTo-Json -Compress
  
} else {
  Write-Error "No forge.toml or hardhat.config.js found. Please use Foundry or Hardhat."
  exit 1
}

if (-not $bytecode) {
  Write-Error "Failed to extract bytecode from compiled artifact"
  exit 1
}

Write-Host "✅ Contract compiled successfully" -ForegroundColor Green

# Encode constructor arguments
Write-Host ""
Write-Host "Encoding constructor arguments..." -ForegroundColor DarkGray
Write-Host "  - name: '$TokenName'" -ForegroundColor DarkGray
Write-Host "  - symbol: '$Symbol'" -ForegroundColor DarkGray
Write-Host "  - decimals: $Decimals" -ForegroundColor DarkGray
Write-Host "  - initialSupply: $InitialSupply" -ForegroundColor DarkGray

# Create constructor argument encoding
$nameEncoded = & cast encode-packed "string" "$TokenName"
$symbolEncoded = & cast encode-packed "string" "$Symbol"
$decimalsEncoded = & cast encode-packed "uint8" "$Decimals"
$supplyEncoded = & cast encode-packed "uint256" "$InitialSupply"

# Using cast to encode constructor parameters
$constructorArgs = & cast abi-encode "constructor(string,string,uint8,uint256)" "$TokenName" "$Symbol" "$Decimals" "$InitialSupply" 2>&1

if ($LASTEXITCODE -ne 0) {
  Write-Error "Failed to encode constructor arguments: $constructorArgs"
  exit 1
}

# Clean up the encoding output
$constructorArgs = $constructorArgs.Trim()

Write-Host "✅ Constructor arguments encoded" -ForegroundColor Green

# Deploy contract
Write-Host ""
Write-Host "📡 Sending deployment transaction..." -ForegroundColor Cyan

$deployCmd = @(
  "cast", "send", "--rpc-url", $RpcUrl,
  "--private-key", $PrivateKey,
  "--data", "$bytecode$constructorArgs"
)

$deployOutput = & $deployCmd[0] @deployCmd[1..($deployCmd.Count - 1)] 2>&1

if ($LASTEXITCODE -ne 0) {
  Write-Error "Deployment failed: $deployOutput"
  exit 1
}

# Parse transaction hash
$txHash = $deployOutput | Select-String -Pattern "transactionHash|0x[a-fA-F0-9]{64}" | Select-Object -First 1
if ($txHash) {
  $txHash = $txHash.ToString().Split()[-1]
  Write-Host "✅ Deployment transaction sent" -ForegroundColor Green
  Write-Host "   TxHash: $txHash" -ForegroundColor Yellow
} else {
  Write-Host "⚠️ Deployment completed but transaction hash unclear" -ForegroundColor Yellow
  Write-Host "Output: $deployOutput" -ForegroundColor DarkGray
}

# Wait for transaction receipt and get contract address
Write-Host ""
Write-Host "⏳ Waiting for transaction confirmation..." -ForegroundColor Cyan

try {
  $receipt = & cast receipt $txHash --rpc-url $RpcUrl 2>&1 | ConvertFrom-Json
  
  if ($receipt.contractAddress) {
    $contractAddress = $receipt.contractAddress
    Write-Host "✅ Contract deployed successfully!" -ForegroundColor Green
    Write-Host "   Contract Address: $contractAddress" -ForegroundColor Green
    Write-Host "   Block Number: $($receipt.blockNumber)" -ForegroundColor DarkGray
    Write-Host "   Gas Used: $($receipt.gasUsed)" -ForegroundColor DarkGray
  } else {
    Write-Error "No contract address in receipt. Deployment may have failed."
    exit 1
  }
} catch {
  Write-Error "Failed to get transaction receipt: $_"
  exit 1
}

# Save deployment info
$deploymentInfo = @{
  timestamp = Get-Date -Format "o"
  network = $RpcUrl
  deployer = $deployer
  contractAddress = $contractAddress
  contractName = $ContractName
  tokenName = $TokenName
  symbol = $Symbol
  decimals = $Decimals
  initialSupply = $InitialSupply
  transactionHash = $txHash
  abi = $abi
} | ConvertTo-Json -Depth 10

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$deploymentFile = "deployment_${Symbol}_${timestamp}.json"
$deploymentInfo | Out-File -FilePath $deploymentFile -Encoding UTF8

Write-Host ""
Write-Host "💾 Deployment information saved to: $deploymentFile" -ForegroundColor Yellow

# Verify on block explorer if requested
if ($Verify -and $VerifyUrl) {
  Write-Host ""
  Write-Host "🔍 Verifying contract on block explorer..." -ForegroundColor Cyan
  Write-Host "Please visit: $VerifyUrl/address/$contractAddress" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "✅ Deployment Complete!" -ForegroundColor Green
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan

exit 0
