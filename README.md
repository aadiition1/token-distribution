<!-- markdown -->
# Token Distribution Suite

A comprehensive PowerShell toolkit for deploying ERC-20/TRC-20 tokens and distributing initial supply across multiple addresses on Ethereum and TRON networks.

## Standards Compliance

- **ERC-20**: Ethereum token standard (OpenZeppelin compatible)
- **TRC-20**: TRON token standard (fully compatible with ERC-20 interface)

## Components

### 1. Smart Contract (`ERC20Token.sol`)

A fully-featured ERC-20/TRC-20 token implementation with:

- ✅ Standard transfer functionality (`transfer`, `transferFrom`)
- ✅ Approval workflow (`approve`, `allowance`)
- ✅ Minting support (owner-controlled token creation)
- ✅ Burning support (token removal)
- ✅ Pause/unpause mechanism (emergency control)
- ✅ Ownership transfer

**Key Functions:**
```solidity
// Standard ERC-20 functions
function transfer(address to, uint256 amount) returns (bool)
function transferFrom(address from, address to, uint256 amount) returns (bool)
function approve(address spender, uint256 amount) returns (bool)
function balanceOf(address account) returns (uint256)
function allowance(address owner, address spender) returns (uint256)

// Extended functionality
function mint(address to, uint256 amount) returns (bool)         // Owner only
function burn(uint256 amount) returns (bool)
function pause()                                                 // Owner only
function unpause()                                              // Owner only

