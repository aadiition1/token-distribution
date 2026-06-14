// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title ERC20Token
 * @dev Implementation of the ERC-20 token standard (also compatible with TRC-20 on TRON)
 * 
 * This contract implements the standard interface for fungible tokens.
 * Features:
 * - Transfer tokens between addresses
 * - Approve spending allowances
 * - Burn tokens (reduce total supply)
 * - Mint tokens (increase total supply)
 */

interface IERC20 {
    // Required Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    // Required View Functions
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    
    // Required Transfer Functions
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract ERC20Token is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    address public owner;
    bool public paused;
    
    event Burn(address indexed from, uint256 value);
    event Mint(address indexed to, uint256 value);
    event Pause();
    event Unpause();
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier whenNotPaused() {
        require(!paused, "Token transfers are paused");
        _;
    }
    
    /**
     * @dev Constructor to initialize token with initial supply
     * @param _name Token name
     * @param _symbol Token symbol
     * @param _decimals Number of decimal places
     * @param _initialSupply Initial token supply (in whole tokens, will be multiplied by 10^decimals)
     */
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply
    ) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        owner = msg.sender;
        paused = false;
        
        // Convert initial supply to smallest unit
        uint256 supply = _initialSupply * (10 ** uint256(_decimals));
        totalSupply = supply;
        balanceOf[msg.sender] = supply;
        
        emit Transfer(address(0), msg.sender, supply);
    }
    
    /**
     * @dev Transfer tokens to a recipient (ERC-20 standard transfer)
     * @param to Recipient address
     * @param value Amount to transfer
     */
    function transfer(address to, uint256 value) external whenNotPaused returns (bool) {
        require(to != address(0), "Cannot transfer to zero address");
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        
        emit Transfer(msg.sender, to, value);
        return true;
    }
    
    /**
     * @dev Transfer tokens from one address to another (ERC-20 standard transferFrom)
     * @param from Sender address
     * @param to Recipient address
     * @param value Amount to transfer
     */
    function transferFrom(address from, address to, uint256 value) external whenNotPaused returns (bool) {
        require(to != address(0), "Cannot transfer to zero address");
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Allowance exceeded");
        
        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;
        
        emit Transfer(from, to, value);
        return true;
    }
    
    /**
     * @dev Approve an address to spend tokens on behalf of the sender
     * @param spender Address to approve
     * @param value Amount to approve
     */
    function approve(address spender, uint256 value) external returns (bool) {
        require(spender != address(0), "Cannot approve zero address");
        
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }
    
    /**
     * @dev Increase the allowance for a spender
     * @param spender Address to approve
     * @param addedValue Amount to add to current allowance
     */
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        require(spender != address(0), "Cannot approve zero address");
        
        allowance[msg.sender][spender] += addedValue;
        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }
    
    /**
     * @dev Decrease the allowance for a spender
     * @param spender Address to approve
     * @param subtractedValue Amount to subtract from current allowance
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        require(spender != address(0), "Cannot approve zero address");
        require(allowance[msg.sender][spender] >= subtractedValue, "Allowance decreased below zero");
        
        allowance[msg.sender][spender] -= subtractedValue;
        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }
    
    /**
     * @dev Mint new tokens (increase total supply) - Owner only
     * @param to Address to receive minted tokens
     * @param value Amount to mint
     */
    function mint(address to, uint256 value) external onlyOwner returns (bool) {
        require(to != address(0), "Cannot mint to zero address");
        
        totalSupply += value;
        balanceOf[to] += value;
        
        emit Transfer(address(0), to, value);
        emit Mint(to, value);
        return true;
    }
    
    /**
     * @dev Burn tokens from sender (decrease total supply)
     * @param value Amount to burn
     */
    function burn(uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        
        balanceOf[msg.sender] -= value;
        totalSupply -= value;
        
        emit Transfer(msg.sender, address(0), value);
        emit Burn(msg.sender, value);
        return true;
    }
    
    /**
     * @dev Burn tokens from another address - requires approval
     * @param from Address to burn from
     * @param value Amount to burn
     */
    function burnFrom(address from, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Allowance exceeded");
        
        balanceOf[from] -= value;
        allowance[from][msg.sender] -= value;
        totalSupply -= value;
        
        emit Transfer(from, address(0), value);
        emit Burn(from, value);
        return true;
    }
    
    /**
     * @dev Pause token transfers - Owner only
     */
    function pause() external onlyOwner {
        paused = true;
        emit Pause();
    }
    
    /**
     * @dev Unpause token transfers - Owner only
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpause();
    }
    
    /**
     * @dev Transfer ownership to a new address
     * @param newOwner Address of the new owner
     */
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Cannot transfer to zero address");
        address previousOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(previousOwner, newOwner);
    }
}
