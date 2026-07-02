#!/usr/bin/env node
/**
 * Token Deployment Wizard
 * Deploy ERC-20 → initial supply goes directly to recipient wallet
 * One transaction. Zero extra cost.
 */

const fs   = require('fs');
const path = require('path');
const argv = process.argv.slice(2);

const envFlagIndex = argv.indexOf('--env');
const envPath =
  envFlagIndex !== -1 && argv[envFlagIndex + 1]
    ? path.resolve(process.cwd(), argv[envFlagIndex + 1])
    : path.join(__dirname, '..', '.env');
require('dotenv').config({ path: envPath });

const { ethers } = require('ethers');
const rl   = require('readline').createInterface({ input: process.stdin, output: process.stdout });
const { saveDeploymentReport } = require('../core/results');

// ── helpers ──────────────────────────────────────────────────────────────────

const C = {
  reset: '\x1b[0m', red: '\x1b[31m', green: '\x1b[32m',
  yellow: '\x1b[33m', cyan: '\x1b[36m', magenta: '\x1b[35m', dim: '\x1b[2m', bold: '\x1b[1m'
};
const c = (col, txt) => `${C[col]}${txt}${C.reset}`;

const ask  = q => new Promise(res => rl.question(q, a => res(a.trim())));
const line = (col='magenta') => console.log(c(col, '─'.repeat(72)));

async function prompt(label, def = '') {
  const hint = def ? c('dim', ` [${def}]`) : '';
  const ans  = await ask(`  ${c('cyan','›')} ${label}${hint}: `);
  return ans || def;
}

async function promptSecret(label) {
  const ans = await ask(`  ${c('cyan','›')} ${label}: `);
  return ans.trim();
}

async function promptValidated(label, def, validate) {
  while (true) {
    const val = await prompt(label, def);
    const err = validate(val);
    if (!err) return val;
    console.log(`  ${c('red','✗')} ${err}`);
  }
}

function info(label, val) {
  console.log(`  ${c('cyan','·')} ${label}: ${c('green', val)}`);
}

function section(title) {
  console.log('');
  line();
  console.log(`  ${c('bold', title)}`);
  line();
  console.log('');
}

// ── networks ─────────────────────────────────────────────────────────────────

const NETWORKS = [
  { label: 'BSC Mainnet',          rpc: 'https://bsc-dataseed1.binance.org',              explorer: 'https://bscscan.com',             testnet: false },
  { label: 'BSC Testnet',          rpc: 'https://data-seed-prebsc-1-s1.binance.org:8545', explorer: 'https://testnet.bscscan.com',      testnet: true  },
  { label: 'Ethereum Mainnet',     rpc: null,                                              explorer: 'https://etherscan.io',            testnet: false, needsKey: true },
  { label: 'Ethereum Sepolia',     rpc: null,                                              explorer: 'https://sepolia.etherscan.io',    testnet: true,  needsKey: true },
  { label: 'Polygon',              rpc: 'https://polygon-rpc.com',                        explorer: 'https://polygonscan.com',         testnet: false },
  { label: 'Arbitrum One',         rpc: 'https://arb1.arbitrum.io/rpc',                   explorer: 'https://arbiscan.io',             testnet: false },
  { label: 'Custom RPC',           rpc: null,                                              explorer: '',                                testnet: false },
];

// ── contract ─────────────────────────────────────────────────────────────────

const artifact = JSON.parse(
  fs.readFileSync(path.join(__dirname, '..', 'contracts', 'ERC20Token.json'), 'utf8')
);

// ── main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.clear();
  console.log('');
  console.log(c('magenta', '┌─────────────────────────────────────────────────────────────────────┐'));
  console.log(c('magenta', '│') + c('bold',    '   🚀  ERC-20 TOKEN DEPLOYMENT WIZARD                               ') + c('magenta','│'));
  console.log(c('magenta', '│') + c('dim',     '   Deploy once → initial supply lands in recipient wallet           ') + c('magenta','│'));
  console.log(c('magenta', '└─────────────────────────────────────────────────────────────────────┘'));
  console.log('');

  const DRY = argv.includes('--dry-run');
  if (DRY) console.log(c('yellow', '  ⚠  DRY-RUN MODE — nothing will be sent\n'));

  // ── STEP 1: Network ────────────────────────────────────────────────────────
  section('STEP 1 — SELECT NETWORK');

  NETWORKS.forEach((n, i) => {
    const tag = n.testnet ? c('dim','[testnet]') : c('green','[mainnet]');
    console.log(`  ${c('yellow', String(i+1)+'.')} ${n.label} ${tag}`);
  });
  console.log('');

  const netIdx = await promptValidated('Choose network', '2', v => {
    const n = parseInt(v);
    return (n >= 1 && n <= NETWORKS.length) ? null : `Enter 1–${NETWORKS.length}`;
  });
  const net = NETWORKS[parseInt(netIdx) - 1];

  let rpcUrl = net.rpc;

  if (net.needsKey) {
    const key = await promptValidated('Enter Infura/Alchemy API key', '', v =>
      v.length > 8 ? null : 'Key too short'
    );
    rpcUrl = net.label.includes('Sepolia')
      ? `https://eth-sepolia.infura.io/v3/${key}`
      : `https://eth-mainnet.infura.io/v3/${key}`;
  }

  if (!rpcUrl) {
    rpcUrl = await promptValidated('Enter custom RPC URL', '', v =>
      v.startsWith('http') ? null : 'Must start with http:// or https://'
    );
  }

  const provider = new ethers.JsonRpcProvider(rpcUrl);

  // verify connection
  try {
    const block = await provider.getBlockNumber();
    info('Connected · latest block', String(block));
  } catch (e) {
    console.log(c('red', `\n  ✗ Cannot connect to RPC: ${e.message}`));
    process.exit(1);
  }

  if (!net.testnet) {
    console.log('');
    console.log(c('yellow', '  ⚠  MAINNET selected — real funds will be used'));
    const ok = await prompt('Type YES to continue on mainnet', '');
    if (ok !== 'YES') { console.log(c('red','  Aborted.')); process.exit(0); }
  }

  // ── STEP 2: Private Key ────────────────────────────────────────────────────
  section('STEP 2 — YOUR WALLET (DEPLOYER)');

  let privateKey = process.env.PRIVATE_KEY || '';
  if (privateKey) {
    console.log(c('dim','  Private key loaded from .env'));
  } else {
    privateKey = await promptSecret('Enter private key (64 hex chars)');
  }

  let wallet;
  try {
    const k = privateKey.startsWith('0x') ? privateKey : `0x${privateKey}`;
    wallet  = new ethers.Wallet(k, provider);
  } catch {
    console.log(c('red','  ✗ Invalid private key')); process.exit(1);
  }

  info('Deployer address', wallet.address);

  const nativeBal = await provider.getBalance(wallet.address);
  info('Native balance', `${ethers.formatEther(nativeBal)} (pays gas)`);

  if (nativeBal === 0n) {
    console.log(c('yellow','\n  ⚠  Balance is 0 — you need native tokens for gas'));
  }

  // ── STEP 3: Token Details ──────────────────────────────────────────────────
  section('STEP 3 — TOKEN DETAILS');

  const tokenName = await promptValidated('Token name', 'My Token', v =>
    v.length > 0 && v.length <= 50 ? null : 'Must be 1–50 characters'
  );
  const symbol = await promptValidated('Token symbol', 'MTK', v =>
    v.length > 0 && v.length <= 10 ? null : 'Must be 1–10 characters'
  );
  const decimals = parseInt(await promptValidated('Decimals', '18', v =>
    /^\d+$/.test(v) && parseInt(v) <= 18 ? null : 'Enter 0–18'
  ));
  const supply = await promptValidated('Initial supply (whole tokens)', '1000000', v =>
    /^\d+$/.test(v) && parseInt(v) > 0 ? null : 'Must be a positive whole number'
  );

  // ── STEP 4: Recipient ──────────────────────────────────────────────────────
  section('STEP 4 — RECIPIENT WALLET');

  console.log(c('dim','  All tokens mint directly here at deploy. Zero extra cost.\n'));

  const recipient = await promptValidated('Recipient wallet address', '', v => {
    try { ethers.getAddress(v); return null; } catch { return 'Invalid EVM address'; }
  });

  // ── STEP 5: Confirm ────────────────────────────────────────────────────────
  section('STEP 5 — CONFIRM & DEPLOY');

  info('Network',          net.label);
  info('Token name',       tokenName);
  info('Symbol',           symbol);
  info('Decimals',         String(decimals));
  info('Initial supply',   `${Number(supply).toLocaleString()} ${symbol}`);
  info('Recipient',        recipient);
  info('Deployer (pays gas)', wallet.address);
  console.log('');

  const go = await prompt('Deploy now? (yes/no)', 'no');
  if (!go.toLowerCase().startsWith('y')) {
    console.log(c('red','\n  Cancelled.\n')); process.exit(0);
  }

  // ── DEPLOY ─────────────────────────────────────────────────────────────────
  section('DEPLOYING...');

  if (DRY) {
    console.log(c('yellow','  ⏭  DRY-RUN: skipping broadcast'));
    console.log(c('green', '\n  ✅ Would deploy successfully\n'));
    rl.close(); return;
  }

  try {
    const factory  = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);
    const supplyBN = BigInt(supply);

    // estimate gas
    const deployTx = await factory.getDeployTransaction(
      tokenName, symbol, decimals, supplyBN, ethers.getAddress(recipient)
    );
    const gasEst = await provider.estimateGas({ ...deployTx, from: wallet.address });
    info('Estimated gas', gasEst.toString());

    console.log(`\n  ${c('cyan','Broadcasting...')}`);

    const contract = await factory.deploy(
      tokenName, symbol, decimals, supplyBN, ethers.getAddress(recipient)
    );

    const deployHash = contract.deploymentTransaction().hash;
    info('Tx hash', deployHash);
    console.log(`  ${c('dim', 'Waiting for confirmation...')}`);

    const receipt = await contract.deploymentTransaction().wait(1);
    const address = await contract.getAddress();

    console.log('');
    console.log(c('green','  ✅ DEPLOYED SUCCESSFULLY'));
    console.log('');
    info('Contract address', address);
    info('Block',            String(receipt.blockNumber));
    info('Gas used',         receipt.gasUsed.toString());
    info('Tx hash',          receipt.hash);
    if (net.explorer) info('Explorer', `${net.explorer}/tx/${receipt.hash}`);

    const reportPath = saveDeploymentReport({
      contractAddress: address,
      txHash: receipt.hash,
      blockNumber: receipt.blockNumber,
      gasUsed: receipt.gasUsed.toString(),
      tokenInfo: {
        name: tokenName,
        symbol,
        decimals,
        supply,
        recipient,
        deployer: wallet.address
      },
      network: net.label
    });
    info('Report saved', path.relative(path.join(__dirname, '..'), reportPath));

  } catch (err) {
    console.log(c('red', `\n  ✗ Deploy failed: ${err.message}`));
    if (process.env.DEBUG) console.error(err);
    process.exit(1);
  }

  console.log('');
  rl.close();
}

main().catch(e => { console.error(e.message); rl.close(); process.exit(1); });
