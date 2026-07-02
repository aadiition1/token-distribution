#!/usr/bin/env node
/**
 * Token Transfer Wizard
 * Send ERC-20 tokens from your wallet to one recipient.
 */

const path = require('path');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });

const { ethers } = require('ethers');
const readline = require('readline');
const {
  getProvider,
  getWallet,
  getNetworkInfo,
  getTokenInfo,
  getBalance,
  getNativeBalance,
  transferToken,
  waitForReceipt,
  isValidAddress,
  isValidPrivateKey
} = require('../core/blockchain');
const { saveDistributionReport } = require('../core/results');

const rl = readline.createInterface({ input: process.stdin, output: process.stdout });

const C = {
  reset: '\x1b[0m', red: '\x1b[31m', green: '\x1b[32m',
  yellow: '\x1b[33m', cyan: '\x1b[36m', magenta: '\x1b[35m', dim: '\x1b[2m', bold: '\x1b[1m'
};
const c = (col, txt) => `${C[col]}${txt}${C.reset}`;

const ask = q => new Promise(res => rl.question(q, a => res(a.trim())));

async function prompt(label, def = '') {
  const hint = def ? c('dim', ` [${def}]`) : '';
  const ans = await ask(`  ${c('cyan', '›')} ${label}${hint}: `);
  return ans || def;
}

async function promptValidated(label, def, validate) {
  while (true) {
    const val = await prompt(label, def);
    const err = validate(val);
    if (!err) return val;
    console.log(`  ${c('red', '✗')} ${err}`);
  }
}

function requireEnv(name) {
  const value = process.env[name];
  if (!value || !value.trim()) {
    throw new Error(`${name} is missing. Add it to .env in the project root.`);
  }
  return value.trim();
}

function validateAmountForDecimals(amount, decimals) {
  if (!/^\d+(\.\d+)?$/.test(amount) || Number(amount) <= 0) {
    return 'Enter a positive token amount';
  }

  const fraction = amount.split('.')[1] || '';
  if (fraction.length > decimals) {
    return `Token supports only ${decimals} decimal places`;
  }

  return null;
}

function info(label, val) {
  console.log(`  ${c('cyan', '·')} ${label}: ${c('green', val)}`);
}

function section(title) {
  console.log('');
  console.log(c('magenta', '─'.repeat(72)));
  console.log(`  ${c('bold', title)}`);
  console.log(c('magenta', '─'.repeat(72)));
  console.log('');
}

async function main() {
  console.clear();
  console.log('');
  console.log(c('magenta', '┌─────────────────────────────────────────────────────────────────────┐'));
  console.log(c('magenta', '│') + c('bold', '   🪂  ERC-20 TOKEN TRANSFER WIZARD                                  ') + c('magenta', '│'));
  console.log(c('magenta', '│') + c('dim', '   Send tokens to one wallet in one transaction                     ') + c('magenta', '│'));
  console.log(c('magenta', '└─────────────────────────────────────────────────────────────────────┘'));
  console.log('');

  section('WALLET');

  let rpcUrl;
  let privateKey;
  try {
    rpcUrl = requireEnv('RPC_URL');
    privateKey = requireEnv('PRIVATE_KEY');
  } catch (err) {
    console.log(c('red', `  ✗ ${err.message}`));
    console.log(c('dim', '  Expected .env next to package.json with RPC_URL and PRIVATE_KEY.'));
    rl.close();
    process.exit(1);
  }

  if (!rpcUrl.startsWith('http://') && !rpcUrl.startsWith('https://')) {
    console.log(c('red', '  ✗ RPC_URL must start with http:// or https://'));
    rl.close();
    process.exit(1);
  }

  if (!isValidPrivateKey(privateKey)) {
    console.log(c('red', '  ✗ PRIVATE_KEY in .env is invalid'));
    rl.close();
    process.exit(1);
  }

  const provider = getProvider(rpcUrl);
  const wallet = getWallet(privateKey, provider);
  const network = await getNetworkInfo(provider);
  const networkName = process.env.NETWORK || network.name || `Chain ${network.chainId}`;

  info('Network', `${networkName} (${network.chainId})`);
  info('Connected latest block', String(network.blockNumber));
  info('Sender wallet', wallet.address);

  const nativeBalance = await getNativeBalance(wallet.address, provider);
  info('Native balance', `${nativeBalance.formatted} (gas)`);

  if (BigInt(nativeBalance.raw) === 0n) {
    console.log(c('red', '\n  ✗ Sender has no native coin for gas.'));
    rl.close();
    process.exit(1);
  }

  section('TRANSFER');

  const tokenAddress = await promptValidated('Contract address', process.env.TOKEN_ADDRESS || '', v =>
    isValidAddress(v) ? null : 'Invalid EVM address'
  );
  const tokenInfo = await getTokenInfo(ethers.getAddress(tokenAddress), provider);

  const amount = await promptValidated('Amount', '', v => validateAmountForDecimals(v, tokenInfo.decimals));
  const recipient = await promptValidated('Wallet address it will land in', '', v =>
    isValidAddress(v) ? null : 'Invalid EVM address'
  );

  const amountRaw = ethers.parseUnits(amount, tokenInfo.decimals);
  const senderTokenBalance = await getBalance(ethers.getAddress(tokenAddress), wallet.address, provider);

  if (BigInt(senderTokenBalance.raw) < amountRaw) {
    console.log(c('red', `\n  ✗ Not enough ${tokenInfo.symbol}.`));
    info('Sender token balance', senderTokenBalance.formatted);
    rl.close();
    process.exit(1);
  }

  const contract = new ethers.Contract(ethers.getAddress(tokenAddress), [
    'function transfer(address to,uint256 amount) returns (bool)'
  ], wallet);
  const estimatedGas = await contract.transfer.estimateGas(ethers.getAddress(recipient), amountRaw);

  console.log('');
  info('Network', networkName);
  info('Contract', ethers.getAddress(tokenAddress));
  info('Token name', tokenInfo.name);
  info('Token symbol', tokenInfo.symbol);
  info('Token decimals', String(tokenInfo.decimals));
  info('Amount', amount);
  info('Sender token balance', senderTokenBalance.formatted);
  info('Estimated gas', estimatedGas.toString());
  info('Recipient', ethers.getAddress(recipient));
  info('Sender', wallet.address);

  const confirm = await prompt('Send now? (yes/no)', 'no');
  if (!confirm.toLowerCase().startsWith('y')) {
    console.log(c('red', '\n  Cancelled.\n'));
    rl.close();
    return;
  }

  section('SENDING');

  try {
    const tx = await transferToken({
      tokenAddress: ethers.getAddress(tokenAddress),
      to: ethers.getAddress(recipient),
      amount: amountRaw,
      wallet
    });

    info('Tx hash', tx.hash);
    console.log(`  ${c('dim', 'Waiting for confirmation...')}`);

    const receipt = await waitForReceipt(tx, 1);
    console.log('');
    console.log(c('green', '  ✅ TRANSFER COMPLETE'));
    console.log('');
    info('Block', String(receipt.blockNumber));
    info('Gas used', receipt.gasUsed);
    info('Status', receipt.status);

    const reportPath = saveDistributionReport({
      tokenAddress: ethers.getAddress(tokenAddress),
      network: networkName,
      chainId: network.chainId,
      recipients: [
        {
          address: ethers.getAddress(recipient),
          amount
        }
      ],
      summary: {
        sender: wallet.address,
        txHash: receipt.txHash,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed,
        status: receipt.status
      }
    });
    info('Report saved', path.relative(path.join(__dirname, '..'), reportPath));
  } catch (err) {
    console.log(c('red', `\n  ✗ Transfer failed: ${err.message}`));
    if (process.env.DEBUG) console.error(err);
    process.exitCode = 1;
  } finally {
    rl.close();
  }
}

main().catch(e => {
  console.error(e.message);
  rl.close();
  process.exit(1);
});
