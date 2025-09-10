# Examples

Practical examples and usage patterns for the EtherSafe inheritance system.

## Basic Setup Example

```solidity
contract BasicInheritanceSetup {
    InheritanceManager public inheritanceManager;
    EIP7702InheritanceController public controller;
    
    constructor() {
        // Deploy core contracts (once per network)
        inheritanceManager = new InheritanceManager();
        controller = new EIP7702InheritanceController(address(inheritanceManager));
    }
    
    function setupMyInheritance() external {
        // Configure inheritance for my EOA
        inheritanceManager.configureInheritance(
            msg.sender,           // My EOA address
            0x456...,            // My inheritor's address
            365 days             // Wait 1 year before inheritance
        );
        
        // Continue using my EOA normally
        // The inheritance system runs in the background
    }
}
```

## Complete Inheritance Flow

```solidity
contract CompleteFlow {
    InheritanceManager public inheritanceManager;
    EIP7702InheritanceController public controller;
    
    // Step 1: Setup (done by EOA owner)
    function setupInheritance(address inheritor, uint256 period) external {
        inheritanceManager.configureInheritance(msg.sender, inheritor, period);
    }
    
    // Step 2: Mark inactivity (can be called by anyone)
    function markAccountInactive(address account) external {
        inheritanceManager.markInactivityStart(
            account,
            block.stateRoot,
            blockhash(block.number - 1),
            "" // State proof (currently unused)
        );
    }
    
    // Step 3: Claim inheritance (called by inheritor after waiting period)
    function claimMyInheritance(address account) external {
        inheritanceManager.claimInheritance(
            account,
            block.stateRoot,
            blockhash(block.number - 1),
            "" // State proof (currently unused)
        );
    }
    
    // Step 4: Control inherited EOA (after EIP-7702 delegation is set up)
    function controlInheritedEOA(address target, uint256 value, bytes calldata data) external {
        // This function would be called on the controller contract
        // after the inherited EOA delegates to it via EIP-7702
        controller.execute(target, value, data);
    }
}
```

## Asset Transfer Examples

### ETH Transfer
```solidity
// Transfer 1 ETH from inherited EOA to recipient
controller.execute(
    recipientAddress,
    1 ether,
    ""
);
```

### ERC20 Token Transfer
```solidity
// Transfer 100 tokens from inherited EOA to recipient
bytes memory transferCall = abi.encodeWithSelector(
    IERC20.transfer.selector,
    recipientAddress,
    100 * 10**18
);

controller.execute(
    tokenAddress,
    0,
    transferCall
);
```

### ERC721 NFT Transfer
```solidity
// Transfer NFT from inherited EOA to recipient
bytes memory nftTransferCall = abi.encodeWithSelector(
    IERC721.transferFrom.selector,
    inheritedEOAAddress,  // from
    recipientAddress,     // to
    tokenId              // tokenId
);

controller.execute(
    nftAddress,
    0,
    nftTransferCall
);
```

### Batch Operations
```solidity
// Transfer multiple assets in one transaction
address[] memory targets = new address[](3);
uint256[] memory values = new uint256[](3);
bytes[] memory calls = new bytes[](3);

// Transfer ETH
targets[0] = recipientAddress;
values[0] = 1 ether;
calls[0] = "";

// Transfer tokens
targets[1] = tokenAddress;
values[1] = 0;
calls[1] = abi.encodeWithSelector(
    IERC20.transfer.selector,
    recipientAddress,
    100 * 10**18
);

// Transfer NFT
targets[2] = nftAddress;
values[2] = 0;
calls[2] = abi.encodeWithSelector(
    IERC721.transferFrom.selector,
    inheritedEOAAddress,
    recipientAddress,
    tokenId
);

controller.executeBatch(targets, values, calls);
```

## DeFi Integration Examples

### Uniswap Token Swap
```solidity
// Swap tokens using inherited EOA
bytes memory swapCall = abi.encodeWithSelector(
    IUniswapV2Router.swapExactTokensForETH.selector,
    amountIn,
    amountOutMin,
    path,
    inheritedEOAAddress,  // recipient (the inherited EOA)
    deadline
);

controller.execute(uniswapRouterAddress, 0, swapCall);
```

### Compound Lending
```solidity
// Supply tokens to Compound using inherited EOA
bytes memory supplyCall = abi.encodeWithSelector(
    ICToken.mint.selector,
    supplyAmount
);

controller.execute(cTokenAddress, 0, supplyCall);
```

### Aave Lending
```solidity
// Deposit into Aave using inherited EOA
bytes memory depositCall = abi.encodeWithSelector(
    ILendingPool.deposit.selector,
    assetAddress,
    amount,
    inheritedEOAAddress,  // onBehalfOf
    0                     // referralCode
);

controller.execute(aaveLendingPoolAddress, 0, depositCall);
```

## JavaScript Integration

### Setting Up EIP-7702 Delegation
```javascript
// After inheritance is claimed, set up EIP-7702 delegation
const eoaAccount = "0x123..."; // The inherited EOA
const controllerAddress = "0x456..."; // EIP7702InheritanceController
const inheritorPrivateKey = "0x789..."; // Inheritor's private key

// Set up EIP-7702 delegation (this makes the EOA delegate to controller)
await setEIP7702Delegation(eoaAccount, controllerAddress);

// Now inheritor can control the EOA directly
const controller = new ethers.Contract(controllerAddress, abi, inheritorSigner);
```

### Controlling the Inherited EOA
```javascript
// Transfer ETH from the inherited EOA
await controller.execute(
    recipientAddress,
    ethers.parseEther("1.0"),
    "0x"
);

// Transfer tokens from the inherited EOA
const transferCall = token.interface.encodeFunctionData("transfer", [
    recipientAddress,
    ethers.parseEther("100")
]);

await controller.execute(tokenAddress, 0, transferCall);

// Execute any transaction from the inherited EOA
await controller.execute(targetContract, value, callData);
```

### Batch Operations in JavaScript
```javascript
// Prepare batch transaction data
const targets = [recipientAddress, tokenAddress, nftAddress];
const values = [ethers.parseEther("1"), 0, 0];
const calls = [
    "0x", // ETH transfer
    token.interface.encodeFunctionData("transfer", [recipient, amount]),
    nft.interface.encodeFunctionData("transferFrom", [from, to, tokenId])
];

// Execute batch
await controller.executeBatch(targets, values, calls);
```

## Production Deployment Guide

### 1. Network Deployment
```solidity
// Deploy once per network
InheritanceManager inheritanceManager = new InheritanceManager();
EIP7702InheritanceController controller = new EIP7702InheritanceController(
    address(inheritanceManager)
);
```

### 2. EOA Configuration
```solidity
// Each EOA owner configures their inheritance
inheritanceManager.configureInheritance(
    eoaAddress,
    inheritorAddress,
    inactivityPeriod
);
```

### 3. Monitoring and Claiming
```solidity
// Monitor for inactive accounts
if (isAccountInactive(eoaAddress)) {
    inheritanceManager.markInactivityStart(eoaAddress, stateRoot, blockHash, proof);
}

// Claim inheritance after waiting period
if (canClaimInheritance(eoaAddress)) {
    inheritanceManager.claimInheritance(eoaAddress, stateRoot, blockHash, proof);
}
```

### 4. EOA Control Transfer
```javascript
// Set up EIP-7702 delegation after inheritance is claimed
await setEIP7702Delegation(inheritedEOA, controllerAddress);

// Inheritor now controls the EOA
const controller = new ethers.Contract(controllerAddress, abi, inheritorSigner);
```

## Security Best Practices

### Access Control Verification
```solidity
// Always verify inheritance is claimed and caller is inheritor
function secureExecute(address target, uint256 value, bytes calldata data) external {
    require(inheritanceManager.isInheritanceClaimed(address(this)), "Not claimed");
    
    (address inheritor,,) = inheritanceManager.getInheritanceConfig(address(this));
    require(msg.sender == inheritor, "Not inheritor");
    
    (bool success,) = target.call{value: value}(data);
    require(success, "Execution failed");
}
```

### State Verification
```solidity
// Verify account state before marking inactivity
function verifyAndMarkInactive(address account) external {
    // Check current account state
    uint256 currentNonce = account.nonce;
    uint256 currentBalance = account.balance;
    
    // Mark inactivity with current state
    inheritanceManager.markInactivityStart(
        account,
        block.stateRoot,
        blockhash(block.number - 1),
        generateStateProof(account, currentNonce, currentBalance)
    );
}
```

## Testing Examples

See the test files for comprehensive examples:
- `test/InheritanceManager.t.sol` - Core inheritance logic tests
- `test/EOAInheritanceViaEIP7702.t.sol` - EIP-7702 integration tests

These tests demonstrate real-world usage patterns and edge cases.
