/**
 * core/blockchain.js
 * Real blockchain engine using ethers.js v6
 * Handles: deploy, transfer, balance queries, receipt polling
 */

const { ethers } = require('ethers');
const fs = require('fs');
const path = require('path');

// ── Load contract artifact ──────────────────────────────────────────────────
const artifactPath = path.join(__dirname, '..', 'contracts', 'ERC20Token.json');
const artifact = JSON.parse(fs.readFileSync(artifactPath, 'utf8'));

// ── Provider & Wallet ───────────────────────────────────────────────────────

function getProvider(rpcUrl) {
  return new ethers.JsonRpcProvider(rpcUrl);
}

function getWallet(privateKey, provider) {
  const key = privateKey.startsWith('0x') ? privateKey : `0x${privateKey}`;
  return new ethers.Wallet(key, provider);
}

// ── Network Info ────────────────────────────────────────────────────────────

async function getNetworkInfo(provider) {
  const network = await provider.getNetwork();
  const block = await provider.getBlockNumber();
  return {
    chainId: network.chainId.toString(),
    name: network.name,
    blockNumber: block
  };
}

// ── Token Info ──────────────────────────────────────────────────────────────

async function getTokenInfo(tokenAddress, provider) {
  const contract = new ethers.Contract(tokenAddress, artifact.abi, provider);
  const [name, symbol, decimals, totalSupply] = await Promise.all([
    contract.name(),
    contract.symbol(),
    contract.decimals(),
    contract.totalSupply()
  ]);
  return {
    address: tokenAddress,
    name,
    symbol,
    decimals: Number(decimals),
    totalSupply: totalSupply.toString(),
    totalSupplyFormatted: ethers.formatUnits(totalSupply, decimals)
  };
}

async function getBalance(tokenAddress, walletAddress, provider) {
  const contract = new ethers.Contract(tokenAddress, artifact.abi, provider);
  const [balance, decimals] = await Promise.all([
    contract.balanceOf(walletAddress),
    contract.decimals()
  ]);
  return {
    raw: balance.toString(),
    formatted: ethers.formatUnits(balance, decimals)
  };
}

async function getNativeBalance(walletAddress, provider) {
  const balance = await provider.getBalance(walletAddress);
  return {
    raw: balance.toString(),
    formatted: ethers.formatEther(balance)
  };
}

// ── Deploy ──────────────────────────────────────────────────────────────────

async function deployToken({ name, symbol, decimals, initialSupply, wallet, gasPrice }) {
  const factory = new ethers.ContractFactory(artifact.abi, artifact.bytecode, wallet);

  const supplyWithDecimals = ethers.parseUnits(initialSupply.toString(), decimals);

  const overrides = {};
  if (gasPrice) {
    overrides.gasPrice = ethers.parseUnits(gasPrice.toString(), 'gwei');
  }

  console.log(`  ⛽ Estimating gas...`);
  const deployTx = await factory.getDeployTransaction(
    name,
    symbol,
    decimals,
    supplyWithDecimals,
    wallet.address,
    overrides
  );

  const gasEstimate = await wallet.provider.estimateGas({ ...deployTx, from: wallet.address });
  console.log(`  ⛽ Estimated gas: ${gasEstimate.toString()}`);

  console.log(`  📡 Broadcasting deployment transaction...`);
  const contract = await factory.deploy(
    name,
    symbol,
    decimals,
    supplyWithDecimals,
    wallet.address,
    overrides
  );

  const deploymentTx = contract.deploymentTransaction();
  console.log(`  🔗 Deploy tx hash: ${deploymentTx.hash}`);
  console.log(`  ⏳ Waiting for confirmation...`);

  const receipt = await deploymentTx.wait(1);
  const contractAddress = await contract.getAddress();

  return {
    contractAddress,
    txHash: receipt.hash,
    blockNumber: receipt.blockNumber,
    gasUsed: receipt.gasUsed.toString(),
    name,
    symbol,
    decimals,
    initialSupply: supplyWithDecimals.toString()
  };
}

// ── Transfer ────────────────────────────────────────────────────────────────

async function transferToken({ tokenAddress, to, amount, wallet, gasPrice, nonce }) {
  const contract = new ethers.Contract(tokenAddress, artifact.abi, wallet);

  const overrides = {};
  if (gasPrice) overrides.gasPrice = ethers.parseUnits(gasPrice.toString(), 'gwei');
  if (nonce !== undefined) overrides.nonce = nonce;

  const tx = await contract.transfer(to, BigInt(amount), overrides);
  return tx;
}

async function waitForReceipt(tx, confirmations = 1) {
  const receipt = await tx.wait(confirmations);
  return {
    txHash: receipt.hash,
    blockNumber: receipt.blockNumber,
    gasUsed: receipt.gasUsed.toString(),
    status: receipt.status === 1 ? 'SUCCESS' : 'FAILED'
  };
}

// ── Gas Price ───────────────────────────────────────────────────────────────

async function suggestGasPrice(provider) {
  const feeData = await provider.getFeeData();
  const gwei = ethers.formatUnits(feeData.gasPrice || feeData.maxFeePerGas || 5n * 10n**9n, 'gwei');
  return parseFloat(gwei).toFixed(2);
}

// ── Validate ────────────────────────────────────────────────────────────────

function isValidAddress(addr) {
  try {
    ethers.getAddress(addr);
    return true;
  } catch {
    return false;
  }
}

function isValidPrivateKey(key) {
  try {
    const k = key.startsWith('0x') ? key : `0x${key}`;
    new ethers.Wallet(k);
    return true;
  } catch {
    return false;
  }
}

function checksumAddress(addr) {
  return ethers.getAddress(addr);
}

module.exports = {
  getProvider,
  getWallet,
  getNetworkInfo,
  getTokenInfo,
  getBalance,
  getNativeBalance,
  deployToken,
  transferToken,
  waitForReceipt,
  suggestGasPrice,
  isValidAddress,
  isValidPrivateKey,
  checksumAddress,
  parseUnits: ethers.parseUnits,
  formatUnits: ethers.formatUnits
};
