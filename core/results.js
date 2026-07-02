/**
 * core/results.js
 * Saves distribution/deployment results to JSON files
 */

const fs = require('fs');
const path = require('path');

function timestamp() {
  return new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
}

function saveResults(type, data, outDir = process.cwd()) {
  const fname = `${type}_${timestamp()}.json`;
  const fpath = path.join(outDir, 'results', fname);

  fs.mkdirSync(path.dirname(fpath), { recursive: true });

  const report = {
    generatedAt: new Date().toISOString(),
    type,
    ...data
  };

  fs.writeFileSync(fpath, JSON.stringify(report, null, 2));
  return fpath;
}

function saveDistributionReport({ tokenAddress, network, chainId, recipients, summary }) {
  return saveResults('distribution', {
    token: tokenAddress,
    network,
    chainId,
    summary,
    recipients
  });
}

function saveDeploymentReport({ contractAddress, txHash, blockNumber, gasUsed, tokenInfo, network, chainId }) {
  return saveResults('deployment', {
    contractAddress,
    txHash,
    blockNumber,
    gasUsed,
    tokenInfo,
    network,
    chainId
  });
}

module.exports = { saveDistributionReport, saveDeploymentReport };
