#Requires -Version 5.1
<#
.Synopsis
   Query ERC-20/TRC-20 token information
.DESCRIPTION
   Retrieves token metadata (name, symbol, decimals, total supply, balance)
   using cast to interact with smart contracts.
   Compliant with ERC-20 and TRC-20 standards.
   
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

if (-not $RpcUrl) {
  Write-Error "RpcUrl not provided and ETH_RPC_URL environment variable not set"
  exit 1
}

$Token = $Token.ToLowerInvariant()
if ($Account) {
  $Account = $Account.ToLowerInvariant()
}

Write-Host "📋 Token Information" -ForegroundColor Cyan
Write-Host "Token Address: $Token" -ForegroundColor Green
Write-Host ""

# Function to call contract read methods
function Invoke-ContractRead {
  param(
    [string]$ContractAddress,
    [string]$Selector,
    [string]$Args = "",
    [string]$RpcUrl
  )
  
  if ($Args) {
    return & cast call $ContractAddress $Selector $Args --rpc-url $RpcUrl 2>&1
  } else {
    return & cast call $ContractAddress "$Selector()" --rpc-url $RpcUrl 2>&1
  }
}

# Get token name
Write-Host "Fetching name()..." -NoNewline -ForegroundColor DarkGray
$name = Invoke-ContractRead -ContractAddress $Token -Selector "name" -RpcUrl $RpcUrl
if ($LASTEXITCODE -eq 0) {
  Write-Host " ✅" -ForegroundColor Green
  Write-Host "  Name: $name" -ForegroundColor White
} else {
  Write-Host " ⚠️ (optional field)" -ForegroundColor Yellow
  $name = $null
}

# Get token symbol
Write-Host "Fetching symbol()..." -NoNewline -ForegroundColor DarkGray
$symbol = Invoke-ContractRead -ContractAddress $Token -Selector "symbol" -RpcUrl $RpcUrl
if ($LASTEXITCODE -eq 0) {
  Write-Host " ✅" -ForegroundColor Green
  Write-Host "  Symbol: $symbol" -ForegroundColor White
} else {
  Write-Host " ⚠️ (optional field)" -ForegroundColor Yellow
  $symbol = $null
}

# Get decimals
Write-Host "Fetching decimals()..." -NoNewline -ForegroundColor DarkGray
$decimals = Invoke-ContractRead -ContractAddress $Token -Selector "decimals" -RpcUrl $RpcUrl
if ($LASTEXITCODE -eq 0) {
  Write-Host " ✅" -ForegroundColor Green
  Write-Host "  Decimals: $decimals" -ForegroundColor White
} else {
  Write-Host " ❌" -ForegroundColor Red
  Write-Error "Failed to fetch decimals"
  exit 1
}

# Get total supply
Write-Host "Fetching totalSupply()..." -NoNewline -ForegroundColor DarkGray
$totalSupplyRaw = Invoke-ContractRead -ContractAddress $Token -Selector "totalSupply" -RpcUrl $RpcUrl
if ($LASTEXITCODE -eq 0) {
  Write-Host " ✅" -ForegroundColor Green
  
  # Convert from wei to human-readable format
  try {
    $divisor = [System.Numerics.BigInteger]::Parse("1" + ("0" * [int]$decimals))
    $totalSupplyBig = [System.Numerics.BigInteger]::Parse($totalSupplyRaw)
    $totalSupplyDisplay = $totalSupplyBig / $divisor
    $remainder = $totalSupplyBig % $divisor
    
    $displayValue = "$totalSupplyDisplay"
    if ($remainder -gt 0) {
      $remainderStr = $remainder.ToString().PadLeft([int]$decimals, '0')
      $displayValue += ".$remainderStr"
    }
    
    Write-Host "  Total Supply: $displayValue $symbol" -ForegroundColor White
    Write-Host "  Total Supply (raw): $totalSupplyRaw" -ForegroundColor DarkGray
  } catch {
    Write-Host "  Total Supply (raw): $totalSupplyRaw" -ForegroundColor White
  }
} else {
  Write-Host " ❌" -ForegroundColor Red
  Write-Error "Failed to fetch total supply"
  exit 1
}

# Get account balance if provided
if ($Account) {
  Write-Host ""
  Write-Host "Fetching balance for $Account..." -NoNewline -ForegroundColor DarkGray
  $balanceRaw = Invoke-ContractRead -ContractAddress $Token -Selector "balanceOf" -Args $Account -RpcUrl $RpcUrl
  if ($LASTEXITCODE -eq 0) {
    Write-Host " ✅" -ForegroundColor Green
    
    try {
      $divisor = [System.Numerics.BigInteger]::Parse("1" + ("0" * [int]$decimals))
      $balanceBig = [System.Numerics.BigInteger]::Parse($balanceRaw)
      $balanceDisplay = $balanceBig / $divisor
      $remainder = $balanceBig % $divisor
      
      $displayValue = "$balanceDisplay"
      if ($remainder -gt 0) {
        $remainderStr = $remainder.ToString().PadLeft([int]$decimals, '0')
        $displayValue += ".$remainderStr"
      }
      
      Write-Host "  Balance: $displayValue $symbol" -ForegroundColor White
      Write-Host "  Balance (raw): $balanceRaw" -ForegroundColor DarkGray
    } catch {
      Write-Host "  Balance (raw): $balanceRaw" -ForegroundColor White
    }
  } else {
    Write-Host " ❌" -ForegroundColor Red
    Write-Error "Failed to fetch balance"
    exit 1
  }
}

Write-Host ""
Write-Host "✅ Token information retrieved successfully" -ForegroundColor Green
