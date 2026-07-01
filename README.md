<!-- markdown -->
# Token Distribution Suite

A PowerShell toolkit for deploying ERC-20 tokens and distributing initial supply across multiple addresses on EVM-compatible networks (Ethereum, Polygon, BSC, etc.).

---

## ⚠️ Prerequisites — Read Before Running

All scripts depend on **Foundry** (`forge` + `cast`).  
Install Foundry: <https://getfoundry.sh>

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

You also need:
- A **funded wallet** private key (the deployer/sender pays gas fees)
- An **EVM-compatible RPC endpoint** (Infura, Alchemy, a local node, etc.)

Set environment variables to avoid typing them each run:

```powershell
$env:ETH_RPC_URL = "https://eth-sepolia.infura.io/v3/YOUR-PROJECT-ID"
$env:PRIVATE_KEY  = "0xYOUR_PRIVATE_KEY"
```

> **Security note:** Never hardcode private keys in scripts or commit them to version control. Use environment variables or a secrets manager.

---

## Components

### Smart Contract (`contracts/ERC20Token.sol`)

A self-contained ERC-20 token with:
- Standard `transfer`, `transferFrom`, `approve`, `allowance`
- Owner-controlled `mint` and `burn`
- Emergency `pause`/`unpause`
- `transferOwnership`

The constructor takes whole-token amounts; the contract internally multiplies by `10^decimals`.

```solidity
constructor(string _name, string _symbol, uint8 _decimals, uint256 _initialSupply)
```

### Wizard (`wizard/OneShot-TokenDistribution.ps1`)

**Start here.** Interactive guided workflow that:
1. Checks prerequisites
2. Collects RPC URL and private key
3. Optionally deploys a new token **or** uses an existing one
4. Loads recipients from a CSV file or accepts manual input
5. Shows the full distribution plan
6. Requires explicit `YES` confirmation before submitting any transaction
7. Reports confirmed on-chain results

```powershell
# From the repo root:
./wizard/OneShot-TokenDistribution.ps1
```

### Scripts (`scripts/`)

Lower-level scripts used by the wizard, also usable standalone.

#### `scripts/Deploy-Token.ps1`

Compiles and deploys `ERC20Token.sol` using `forge create`, waits for on-chain confirmation, and verifies the receipt status before reporting success.

```powershell
.\scripts\Deploy-Token.ps1 `
  -TokenName "My Token" -Symbol "MTK" -Decimals 18 -InitialSupply 1000000 `
  -RpcUrl "https://eth-sepolia.infura.io/v3/YOUR-KEY"
```

Writes a `deployment_<SYMBOL>_<timestamp>.json` file with the contract address and tx hash.

#### `scripts/Send-InitialSupply.ps1`

Sends ERC-20 tokens (or native ETH) to a list of recipients. Each transaction is confirmed on-chain; the receipt status is checked before marking a transfer as successful.

```powershell
$recipients = @(
    [PSCustomObject]@{ address = "0x1234..."; amount = "10000" },
    [PSCustomObject]@{ address = "0xABCD..."; amount = "5000"  }
)

.\scripts\Send-InitialSupply.ps1 `
  -Token      "0xYOUR_TOKEN_ADDRESS" `
  -Decimals   18 `
  -Recipients $recipients `
  -RpcUrl     "https://eth-sepolia.infura.io/v3/YOUR-KEY" `
  -Delay      2
```

Writes a `distribution_results_<timestamp>.json` with per-recipient status and tx hashes.

Use `-Dry` for a dry-run that validates inputs without submitting transactions.

#### `scripts/Get-TokenInfo.ps1`

Reads on-chain token metadata (name, symbol, decimals, total supply, optional balance).

```powershell
.\scripts\Get-TokenInfo.ps1 -Token "0xYOUR_TOKEN_ADDRESS" -Account "0xOPTIONAL_WALLET"
```

---

## Recipients CSV Format

The wizard accepts a UTF-8 CSV file with a header row and two columns:

```csv
address,amount
0x742d35Cc6634C0532925a3b844Bc9e7595f42bE7,100000
0x8ba1f109551bD432803012645Ac136ddd64DBA72,50000
```

- `address` — 0x-prefixed EVM address (checksummed or lowercase)
- `amount` — whole-token count (e.g. `1000` = 1 000 tokens; decimals supported, e.g. `0.5`)

See `examples/recipients.csv` for a complete example.

---

## End-to-End Example (Scripted)

See `examples/distribution-example.ps1` for a fully scripted (non-interactive) example that deploys a token and distributes it.

```powershell
# From the repo root:
$env:ETH_RPC_URL = "https://eth-sepolia.infura.io/v3/YOUR-KEY"
$env:PRIVATE_KEY  = "0xYOUR_PRIVATE_KEY"

.\examples\distribution-example.ps1
```

---

## Error Handling

Every script:
- Exits with code `1` on any error
- Verifies on-chain receipt status (`0x1` = success) before reporting success
- Never prints "success" based on command exit code alone

If a script exits with a non-zero code, no success message is printed. Check the error output and the result JSON files for details.

---

## Supported Networks

Any EVM-compatible network is supported. Tested on:
- Ethereum mainnet / Sepolia testnet
- Polygon (MATIC)
- BNB Smart Chain
- Any network with a Foundry-compatible JSON-RPC endpoint

