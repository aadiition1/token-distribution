#Requires -Version 5.1
<#
.Synopsis
   Distribute initial token supply to multiple recipients
.DESCRIPTION
   Sends an initial token supply to multiple addresses from a deployment wallet.
   Supports both native coins (ETH/TRX) and ERC20/TRC20 tokens.
   Compliant with ERC-20 and TRC-20 standards.
   
.EXAMPLE
   $recipients = @(
       @{ address = "0x1234..."; amount = "10000" },
       @{ address = "0x5678..."; amount = "50000" }
   )
   .\Send-InitialSupply.ps1 -Token "0xabcd..." -Decimals "18" -Recipients $recipients
   
.EXAMPLE
   .\Send-InitialSupply.ps1 -Eth -Recipients @(@{ address = "0x1234..."; amount = "10" })

.INPUTS
   Recipient objects with 'address' and 'amount' properties

.OUTPUTS
   Transaction hashes and delivery status for each recipient
#>

param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [PSObject[]]$Recipients,

  [string]$RpcUrl = $env:ETH_RPC_URL,
  [string]$PrivateKey = $env:PRIVATE_KEY,
  [switch]$Eth,
  [string]$Token,
  [string]$Decimals = "18",
  [int]$Delay = 0,
  [switch]$Dry
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

if (-not $Eth -and -not $Token) {
  Write-Error "Must specify either -Eth flag for native token or -Token parameter for ERC20/TRC20"
  exit 1
}

# Get sender address
$senderAddress = & cast wallet address --private-key $PrivateKey 2>$null
if ($LASTEXITCODE -ne 0) {
  Write-Error "Failed to derive address from private key"
  exit 1
}

Write-Host "🚀 Starting Initial Supply Distribution" -ForegroundColor Cyan
Write-Host "Sender: $senderAddress" -ForegroundColor Green
Write-Host "Recipients: $($Recipients.Count)" -ForegroundColor Yellow
Write-Host "RPC URL: $RpcUrl" -ForegroundColor DarkGray

if ($Dry) {
  Write-Host "📋 DRY RUN MODE - No transactions will be sent" -ForegroundColor Yellow
}

Write-Host ""

# Storage for results
$results = @()
$successCount = 0
$failureCount = 0

# Process each recipient
foreach ($i in 0..($Recipients.Count - 1)) {
  $recipient = $Recipients[$i]
  $recipientAddress = $recipient.address.Trim().ToLowerInvariant()
  $amount = $recipient.amount
  
  # Validate recipient
  if (-not ($recipientAddress -match '^0x[a-f0-9]{40}$')) {
    Write-Host "❌ Invalid address format: $recipientAddress" -ForegroundColor Red
    $results += @{
      Index = $i + 1
      Address = $recipientAddress
      Amount = $amount
      Status = "FAILED"
      Error = "Invalid address format"
      TxHash = $null
    }
    $failureCount++
    continue
  }
  
  Write-Host "[$($i + 1)/$($Recipients.Count)] Sending $amount to $recipientAddress..." -NoNewline -ForegroundColor Cyan
  
  # Build send command
  if ($Eth) {
    $cmd = @("cast", "send", $recipientAddress, "--value", $amount, "--rpc-url", $RpcUrl, "--private-key", $PrivateKey)
  } else {
    $nativeToken = "0x0000000000000000000000000000000000000000"
    $normalizedToken = $Token.Trim().ToLowerInvariant()
    
    # ERC20/TRC20 transfer encoding (function selector: a9059cbb)
    # Implements: transfer(address _to, uint256 _value)
    $selector = "0xa9059cbb"
    $encodedTo = $recipientAddress.Substring(2).PadLeft(64, '0')
    $rawAmount = & cast to-wei $amount eth --decimals $Decimals
    
    if ($LASTEXITCODE -ne 0) {
      Write-Host " ❌" -ForegroundColor Red
      Write-Host "   Error: Failed to convert amount to wei" -ForegroundColor Red
      $results += @{
        Index = $i + 1
        Address = $recipientAddress
        Amount = $amount
        Status = "FAILED"
        Error = "Failed to convert amount"
        TxHash = $null
      }
      $failureCount++
      continue
    }
    
    $encodedAmount = ([System.Numerics.BigInteger]::Parse($rawAmount)).ToString("x").PadLeft(64, '0')
    $data = "$selector$encodedTo$encodedAmount"
    
    $cmd = @("cast", "send", $normalizedToken, "--data", $data, "--rpc-url", $RpcUrl, "--private-key", $PrivateKey)
  }
  
  if ($Dry) {
    Write-Host " ⏭️ (dry run)" -ForegroundColor Yellow
    $results += @{
      Index = $i + 1
      Address = $recipientAddress
      Amount = $amount
      Status = "SIMULATED"
      Error = $null
      TxHash = "0x0000000000000000000000000000000000000000000000000000000000000000"
    }
  } else {
    try {
      $txHash = & $cmd[0] @cmd[1..($cmd.Count - 1)] 2>&1
      
      if ($LASTEXITCODE -eq 0) {
        Write-Host " ✅" -ForegroundColor Green
        Write-Host "   TxHash: $txHash" -ForegroundColor DarkGray
        $results += @{
          Index = $i + 1
          Address = $recipientAddress
          Amount = $amount
          Status = "SUCCESS"
          Error = $null
          TxHash = $txHash
        }
        $successCount++
      } else {
        Write-Host " ❌" -ForegroundColor Red
        Write-Host "   Error: $txHash" -ForegroundColor Red
        $results += @{
          Index = $i + 1
          Address = $recipientAddress
          Amount = $amount
          Status = "FAILED"
          Error = $txHash
          TxHash = $null
        }
        $failureCount++
      }
    } catch {
      Write-Host " ❌" -ForegroundColor Red
      Write-Host "   Exception: $_" -ForegroundColor Red
      $results += @{
        Index = $i + 1
        Address = $recipientAddress
        Amount = $amount
        Status = "FAILED"
        Error = $_.Exception.Message
        TxHash = $null
      }
      $failureCount++
    }
  }
  
  # Add delay between transactions if specified
  if ($Delay -gt 0 -and $i -lt ($Recipients.Count - 1)) {
    Start-Sleep -Seconds $Delay
  }
}

# Summary
Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "📊 Distribution Summary" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Total Recipients: $($Recipients.Count)" -ForegroundColor White
Write-Host "✅ Successful: $successCount" -ForegroundColor Green
Write-Host "❌ Failed: $failureCount" -ForegroundColor Red

# Export results
$resultsJson = $results | ConvertTo-Json -Depth 10
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = "distribution_results_$timestamp.json"

$resultsJson | Out-File -FilePath $outputFile -Encoding UTF8
Write-Host ""
Write-Host "📁 Results saved to: $outputFile" -ForegroundColor Yellow

exit $(if ($failureCount -eq 0) { 0 } else { 1 })
