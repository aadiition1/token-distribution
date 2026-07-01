#Requires -Version 5.1
<#
.Synopsis
   Distribute ERC-20 tokens (or native ETH) to multiple recipients
.DESCRIPTION
   Sends tokens to multiple addresses from a funded wallet.
   Supports both native ETH and ERC-20 tokens.
   Requires Foundry (cast) to be installed: https://getfoundry.sh

   Each transaction is confirmed on-chain before the script moves to the next
   recipient. The script reports FAILED if the transaction reverts, rather than
   silently treating a revert as success.

.EXAMPLE
   $recipients = @(
       @{ address = "0x1234..."; amount = "1000" },
       @{ address = "0x5678..."; amount = "500" }
   )
   .\Send-InitialSupply.ps1 -Token "0xabcd..." -Decimals 18 -Recipients $recipients `
       -RpcUrl "https://eth-sepolia.infura.io/v3/YOUR-KEY"

.EXAMPLE
   # Native ETH distribution (amount in ETH, e.g. "0.1")
   .\Send-InitialSupply.ps1 -Eth -Recipients @(@{ address = "0x1234..."; amount = "0.1" })

.INPUTS
   Recipient objects with 'address' (checksummed or lowercase 0x-prefixed) and
   'amount' (whole-token count, or ETH amount for -Eth mode) properties.

.OUTPUTS
   Transaction hashes and confirmed on-chain status for each recipient.
   A JSON results file is written at the end.
#>

param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [PSObject[]]$Recipients,

  [string]$RpcUrl     = $env:ETH_RPC_URL,
  [string]$PrivateKey = $env:PRIVATE_KEY,
  [switch]$Eth,
  [string]$Token,
  [string]$Decimals = "18",
  [int]$Delay       = 0,
  [switch]$Dry
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Prerequisite check ─────────────────────────────────────────────────────────

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

if (-not $Eth -and -not $Token) {
  Write-Error "Must specify either -Eth flag for native ETH or -Token <address> for ERC-20."
  exit 1
}

if ($Token -and $Token -notmatch '^0x[a-fA-F0-9]{40}$') {
  Write-Error "Token address is not a valid 0x-prefixed 40-hex-character address: '$Token'"
  exit 1
}

$decimalsInt = [int]$Decimals
if ($decimalsInt -lt 0 -or $decimalsInt -gt 255) {
  Write-Error "Decimals must be between 0 and 255. Got: $Decimals"
  exit 1
}

# ── Helper: convert human amount → smallest token unit (BigInteger string) ────

function ConvertTo-TokenUnits {
  param([string]$Amount, [int]$Decimals)

  $Amount = $Amount.Trim()

  if ($Amount -match '^(\d+)\.(\d+)$') {
    $intPart  = $Matches[1]
    $fracPart = $Matches[2]
    if ($fracPart.Length -gt $Decimals) {
      throw "Amount '$Amount' has $($fracPart.Length) decimal places but token only supports $Decimals."
    }
    $fracPart = $fracPart.PadRight($Decimals, '0')
    return [System.Numerics.BigInteger]::Parse($intPart + $fracPart).ToString()
  } elseif ($Amount -match '^\d+$') {
    $n = [System.Numerics.BigInteger]::Parse($Amount)
    $m = [System.Numerics.BigInteger]::Pow(10, $Decimals)
    return ($n * $m).ToString()
  } else {
    throw "Invalid amount format: '$Amount'. Expected an integer or decimal number (e.g. '1000' or '0.5')."
  }
}

# ── Derive sender address ──────────────────────────────────────────────────────

$senderAddress = (& cast wallet address --private-key $PrivateKey 2>&1)
if ($LASTEXITCODE -ne 0) {
  Write-Error "Failed to derive address from private key: $senderAddress"
  exit 1
}
$senderAddress = $senderAddress.Trim()

Write-Host ""
Write-Host "🚀 Starting Token Distribution" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Sender    : $senderAddress" -ForegroundColor Green
if ($Token) {
  Write-Host "Token     : $Token" -ForegroundColor Green
  Write-Host "Decimals  : $Decimals" -ForegroundColor Green
} else {
  Write-Host "Asset     : Native ETH" -ForegroundColor Green
}
Write-Host "Recipients: $($Recipients.Count)" -ForegroundColor Yellow
Write-Host "RPC URL   : $RpcUrl" -ForegroundColor DarkGray

if ($Dry) {
  Write-Host ""
  Write-Host "📋 DRY RUN MODE — No transactions will be submitted." -ForegroundColor Yellow
}

Write-Host ""

# ── Process each recipient ─────────────────────────────────────────────────────

$results      = @()
$successCount = 0
$failureCount = 0

foreach ($i in 0..($Recipients.Count - 1)) {
  $recipient        = $Recipients[$i]
  $recipientAddress = $recipient.address.Trim()
  $amount           = "$($recipient.amount)".Trim()

  # Validate address (accept mixed-case checksummed or lowercase)
  if (-not ($recipientAddress -match '^0x[a-fA-F0-9]{40}$')) {
    Write-Host "[$($i+1)/$($Recipients.Count)] ❌ Invalid address: $recipientAddress" -ForegroundColor Red
    $results += [ordered]@{
      index   = $i + 1
      address = $recipientAddress
      amount  = $amount
      status  = "FAILED"
      error   = "Invalid address format"
      txHash  = $null
    }
    $failureCount++
    continue
  }

  Write-Host "[$($i+1)/$($Recipients.Count)] Sending $amount to $recipientAddress..." `
    -NoNewline -ForegroundColor Cyan

  # ── Build cast send command ─────────────────────────────────────────────────

  if ($Dry) {
    Write-Host " ⏭️  (dry run)" -ForegroundColor Yellow
    $results += [ordered]@{
      index   = $i + 1
      address = $recipientAddress
      amount  = $amount
      status  = "DRY_RUN"
      error   = $null
      txHash  = $null
    }
    continue
  }

  try {
    if ($Eth) {
      # Native ETH: cast send <to> --value <amount in ether> --json
      $cmd = @(
        "cast", "send",
        $recipientAddress,
        "--value", "${amount}ether",
        "--rpc-url", $RpcUrl,
        "--private-key", $PrivateKey,
        "--json"
      )
    } else {
      # ERC-20: compute amount in smallest unit, then call transfer(address,uint256)
      $rawAmount = ConvertTo-TokenUnits -Amount $amount -Decimals $decimalsInt

      $cmd = @(
        "cast", "send",
        $Token,
        "transfer(address,uint256)",
        $recipientAddress,
        $rawAmount,
        "--rpc-url", $RpcUrl,
        "--private-key", $PrivateKey,
        "--json"
      )
    }

    $txOutput  = (& $cmd[0] $cmd[1..($cmd.Count - 1)] 2>&1) -join "`n"
    $castExit  = $LASTEXITCODE

    if ($castExit -ne 0) {
      Write-Host " ❌" -ForegroundColor Red
      Write-Host "   cast send failed: $txOutput" -ForegroundColor Red
      $results += [ordered]@{
        index   = $i + 1
        address = $recipientAddress
        amount  = $amount
        status  = "FAILED"
        error   = $txOutput
        txHash  = $null
      }
      $failureCount++
    } else {
      # Parse receipt JSON returned by cast send --json
      $receipt = $txOutput | ConvertFrom-Json
      $txHash  = $receipt.transactionHash

      # Verify on-chain success. cast --json returns status as a hex string ("0x1" = success).
      # Normalize to integer before comparing.
      $statusInt = if ($receipt.status -is [string] -and $receipt.status.StartsWith("0x")) {
        [Convert]::ToInt32($receipt.status, 16)
      } else {
        [int]$receipt.status
      }

      if ($statusInt -ne 1) {
        Write-Host " ❌" -ForegroundColor Red
        Write-Host "   Transaction REVERTED on-chain (status=$($receipt.status)). TxHash: $txHash" -ForegroundColor Red
        $results += [ordered]@{
          index   = $i + 1
          address = $recipientAddress
          amount  = $amount
          status  = "REVERTED"
          error   = "Transaction reverted on-chain"
          txHash  = $txHash
        }
        $failureCount++
      } else {
        Write-Host " ✅" -ForegroundColor Green
        Write-Host "   TxHash: $txHash" -ForegroundColor DarkGray
        $results += [ordered]@{
          index   = $i + 1
          address = $recipientAddress
          amount  = $amount
          status  = "SUCCESS"
          error   = $null
          txHash  = $txHash
        }
        $successCount++
      }
    }
  } catch {
    Write-Host " ❌" -ForegroundColor Red
    Write-Host "   Exception: $($_.Exception.Message)" -ForegroundColor Red
    $results += [ordered]@{
      index   = $i + 1
      address = $recipientAddress
      amount  = $amount
      status  = "FAILED"
      error   = $_.Exception.Message
      txHash  = $null
    }
    $failureCount++
  }

  # Delay between transactions
  if ($Delay -gt 0 -and $i -lt ($Recipients.Count - 1)) {
    Write-Host "   ⏳ Waiting $Delay second(s) before next transaction..." -ForegroundColor DarkGray
    Start-Sleep -Seconds $Delay
  }
}

# ── Summary ────────────────────────────────────────────────────────────────────

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "📊 Distribution Summary" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
Write-Host "Total Recipients: $($Recipients.Count)" -ForegroundColor White
Write-Host "✅ Successful   : $successCount" -ForegroundColor Green
Write-Host "❌ Failed       : $failureCount" -ForegroundColor $(if ($failureCount -gt 0) { "Red" } else { "White" })

# Export results
$ts         = Get-Date -Format "yyyyMMdd_HHmmss"
$outputFile = "distribution_results_${ts}.json"
$results | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile -Encoding UTF8
Write-Host ""
Write-Host "📁 Results saved to: $outputFile" -ForegroundColor Yellow

if ($Dry) {
  Write-Host ""
  Write-Host "ℹ️  This was a dry run. No transactions were submitted." -ForegroundColor Yellow
  exit 0
}

exit $(if ($failureCount -eq 0) { 0 } else { 1 })
