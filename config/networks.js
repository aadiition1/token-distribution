/**
 * config/networks.js
 * Supported networks with RPC URLs, chain IDs and block explorers
 */

module.exports = {
  networks: [
    {
      id: 'eth-mainnet',
      label: 'Ethereum Mainnet',
      rpc: 'https://eth-mainnet.infura.io/v3/YOUR_KEY',
      chainId: 1,
      explorer: 'https://etherscan.io',
      needsKey: true,
      symbol: 'ETH',
      testnet: false
    },
    {
      id: 'eth-sepolia',
      label: 'Ethereum Sepolia (testnet)',
      rpc: 'https://eth-sepolia.infura.io/v3/YOUR_KEY',
      chainId: 11155111,
      explorer: 'https://sepolia.etherscan.io',
      needsKey: true,
      symbol: 'ETH',
      testnet: true
    },
    {
      id: 'bsc-mainnet',
      label: 'BSC Mainnet (Binance Smart Chain)',
      rpc: 'https://bsc-dataseed1.binance.org',
      chainId: 56,
      explorer: 'https://bscscan.com',
      needsKey: false,
      symbol: 'BNB',
      testnet: false
    },
    {
      id: 'bsc-testnet',
      label: 'BSC Testnet',
      rpc: 'https://data-seed-prebsc-1-s1.binance.org:8545',
      chainId: 97,
      explorer: 'https://testnet.bscscan.com',
      needsKey: false,
      symbol: 'tBNB',
      testnet: true
    },
    {
      id: 'polygon',
      label: 'Polygon Mainnet',
      rpc: 'https://polygon-rpc.com',
      chainId: 137,
      explorer: 'https://polygonscan.com',
      needsKey: false,
      symbol: 'MATIC',
      testnet: false
    },
    {
      id: 'polygon-mumbai',
      label: 'Polygon Mumbai (testnet)',
      rpc: 'https://rpc-mumbai.maticvigil.com',
      chainId: 80001,
      explorer: 'https://mumbai.polygonscan.com',
      needsKey: false,
      symbol: 'MATIC',
      testnet: true
    },
    {
      id: 'arbitrum',
      label: 'Arbitrum One',
      rpc: 'https://arb1.arbitrum.io/rpc',
      chainId: 42161,
      explorer: 'https://arbiscan.io',
      needsKey: false,
      symbol: 'ETH',
      testnet: false
    },
    {
      id: 'custom',
      label: 'Custom RPC URL',
      rpc: null,
      chainId: null,
      explorer: '',
      needsKey: false,
      symbol: 'ETH',
      testnet: false
    }
  ],

  getByIndex(i) {
    return this.networks[i];
  },

  getById(id) {
    return this.networks.find(n => n.id === id);
  }
};
