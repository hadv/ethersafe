# Getting Started

This guide walks you through setting up and using the EtherSafe inheritance system.

## Prerequisites

- Solidity ^0.8.20
- Foundry for testing and deployment
- Understanding of EIP-7702 delegation

## Installation

1. Clone the repository:
```bash
git clone https://github.com/hadv/ethersafe.git
cd ethersafe
```

2. Install dependencies:
```bash
forge install
```

3. Run tests:
```bash
forge test
```

## Deployment

### 1. Deploy Core Contracts

```solidity
// Deploy the inheritance manager (once per network)
InheritanceManager inheritanceManager = new InheritanceManager();

// Deploy the EIP-7702 controller (once per network)
EIP7702InheritanceController controller = new EIP7702InheritanceController(
    address(inheritanceManager)
);
```

### 2. Configure Inheritance for an EOA

```solidity
// EOA owner configures inheritance
address eoaAddress = 0x123...; // The EOA to inherit
address inheritor = 0x456...;  // Who will inherit
uint256 inactivityPeriod = 365 days; // How long to wait

// Call from the EOA owner
inheritanceManager.configureInheritance(
    eoaAddress,
    inheritor,
    inactivityPeriod
);
```

### 3. Set Up EIP-7702 Delegation (Recommended)

```javascript
// Set up delegation during setup phase (recommended approach)
await setEIP7702Delegation(eoaAddress, controllerAddress);

// Now the EOA is delegated to the controller, but only the inheritor
// can use it after inheritance is claimed
```

## Basic Usage

### Step 1: Normal Operations

After configuring inheritance, the EOA continues normal operations. The inheritance system runs in the background without affecting daily usage.

```solidity
// EOA can use any existing wallet or EIP-7702 delegator
// Inheritance is completely separate from daily operations
```

### Step 2: Inactivity Detection

When an account becomes inactive, anyone can mark the start of the inactivity period:

```solidity
// Anyone can call this when they notice an account is inactive
inheritanceManager.markInactivityStart(
    eoaAddress,
    currentStateRoot,  // Current block's state root
    currentBlockHash,  // Current block hash
    stateProof        // Merkle proof of account state
);
```

### Step 3: Claim Inheritance

After the inactivity period expires, the inheritor can claim inheritance:

```solidity
// Inheritor claims inheritance after waiting period
inheritanceManager.claimInheritance(
    eoaAddress,
    currentStateRoot,  // Current block's state root
    currentBlockHash,  // Current block hash
    stateProof        // Merkle proof showing account still inactive
);
```

### Step 4: Control the Inherited EOA

Once inheritance is claimed, the inheritor can immediately control the EOA (delegation already set up):

```javascript
// Inheritor can now control the EOA directly (delegation was set up in step 3)
const controller = new ethers.Contract(controllerAddress, abi, inheritorSigner);

// Transfer ETH from the inherited EOA
await controller.execute(recipientAddress, ethers.parseEther("1.0"), "0x");

// Transfer tokens from the inherited EOA
const transferCall = token.interface.encodeFunctionData("transfer", [
    recipientAddress,
    ethers.parseEther("100")
]);
await controller.execute(tokenAddress, 0, transferCall);
```

**Alternative: Post-Inheritance Delegation**

If delegation wasn't set up during the setup phase:

```javascript
// Set up EIP-7702 delegation after inheritance is claimed
// (requires EOA's private key or pre-signed authorization)
await setEIP7702Delegation(eoaAddress, controllerAddress);
```

## Example: Complete Flow

```solidity
contract ExampleUsage {
    InheritanceManager public inheritanceManager;
    EIP7702InheritanceController public controller;
    
    function setupInheritance() external {
        // 1. Deploy contracts (done once per network)
        inheritanceManager = new InheritanceManager();
        controller = new EIP7702InheritanceController(address(inheritanceManager));
        
        // 2. Configure inheritance for your EOA
        inheritanceManager.configureInheritance(
            msg.sender,           // Your EOA address
            inheritorAddress,     // Who inherits
            365 days             // Wait 1 year
        );
        
        // 3. Continue using your EOA normally
        // The inheritance system runs in the background
    }
    
    function claimMyInheritance(address eoaToInherit) external {
        // 4. After inactivity period, claim inheritance
        inheritanceManager.claimInheritance(
            eoaToInherit,
            block.stateRoot,
            blockhash(block.number - 1),
            stateProof
        );
        
        // 5. Set up EIP-7702 delegation (off-chain)
        // 6. Control the inherited EOA through the controller
    }
}
```

## Next Steps

- Read the [Architecture Guide](./architecture.md) to understand the technical design
- Check the [API Reference](./api-reference.md) for detailed function documentation
- Review [Security Considerations](./security.md) before production use
- See [Examples](./examples.md) for more usage patterns
