# ERC-20 Token Deployment Wizard

Deploy an ERC-20 token and mint the initial supply directly to a recipient wallet in one transaction.

## What it does

- Guides you through network selection
- Uses your deployer wallet to pay gas
- Deploys the token contract
- Mints the full initial supply to a recipient address
- Saves a deployment report in `results/`

## Quick Start

### Requirements

- Node.js 18+

### Run

| Platform | Command |
| --- | --- |
| Windows PowerShell | `.\run.ps1` |
| Windows CMD | `run.bat` |
| Linux / macOS | `bash run.sh` |
| Direct Node.js | `node wizard/run.js` |

Dependencies install automatically on first run.

## Configuration

You can create a `.env` file from `.env.example` to skip prompts:

```env
PRIVATE_KEY=0xYOUR_PRIVATE_KEY_HERE
RPC_URL=https://bsc-dataseed1.binance.org
```

## Dry Run

```bash
node wizard/run.js --dry-run
```

## Output

Deployment reports are written to `results/deploy_<timestamp>.json`.

## Security Notes

- Never commit private keys or live RPC credentials
- The deployer key is only used in memory during the session
- Always test on a testnet before using mainnet funds
