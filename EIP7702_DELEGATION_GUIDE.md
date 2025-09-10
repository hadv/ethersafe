# EIP-7702 Delegation Guide for EtherSafe

This guide explains when and how to set up EIP-7702 delegation in the EtherSafe inheritance system.

## 🎯 Overview

EIP-7702 delegation can be set up at two different phases:

1. **Setup Phase** (Recommended) - During initial inheritance configuration
2. **Post-Inheritance Phase** - After inheritance has been claimed

## 🚀 Approach 1: Setup Phase Delegation (Recommended)

### When to Use
- **Most practical approach** for most users
- **Higher security** - delegation is ready when needed
- **Simpler workflow** - no additional steps after inheritance
- **Better UX** - inheritor can immediately access assets

### How It Works

```javascript
// Step 1: Configure inheritance
await inheritanceManager.configureInheritance(
    eoaAddress,
    inheritorAddress,
    inactivityPeriod
);

// Step 2: Set up delegation immediately (recommended)
await setEIP7702Delegation(eoaAddress, controllerAddress);

// Step 3: EOA continues normal operations
// The controller is delegated but only allows inheritor access after inheritance is claimed
```

### Security Model
- **Controller enforces inheritance verification** - Even though delegation is set up, the controller only allows the inheritor to execute transactions after inheritance is properly claimed
- **No premature access** - The inheritor cannot access the EOA until the inheritance process is complete
- **Immediate availability** - Once inheritance is claimed, the inheritor can immediately control the EOA

### Benefits
✅ **Practical**: No need to access EOA's private key after inheritance  
✅ **Secure**: Controller enforces inheritance verification  
✅ **Immediate**: Inheritor can access assets right after claiming  
✅ **Simple**: One-time setup during configuration  

### Code Example

<augment_code_snippet path="src/EIP7702InheritanceController.sol" mode="EXCERPT">
````solidity
function execute(address to, uint256 value, bytes calldata data) external payable returns (bytes memory) {
    // Verify that inheritance has been claimed for this EOA
    require(inheritanceManager.isInheritanceClaimed(address(this)), "Inheritance not claimed");
    
    // Verify that the caller is the inheritor
    (address inheritor,,) = inheritanceManager.getInheritanceConfig(address(this));
    require(msg.sender == inheritor, "Not the inheritor");
    
    // Execute the transaction from the EOA
    (bool success, bytes memory result) = to.call{value: value}(data);
    require(success, "Execution failed");
    
    return result;
}
````
</augment_code_snippet>

## 🔄 Approach 2: Post-Inheritance Delegation

### When to Use
- **Special scenarios** where setup phase delegation isn't possible
- **Existing EOAs** that already have other delegation setups
- **Complex inheritance arrangements** with multiple phases

### How It Works

```javascript
// Step 1: Configure inheritance (no delegation yet)
await inheritanceManager.configureInheritance(
    eoaAddress,
    inheritorAddress,
    inactivityPeriod
);

// Step 2: EOA continues normal operations with existing delegation

// Step 3: After inheritance is claimed
await inheritanceManager.claimInheritance(eoaAddress, stateProof);

// Step 4: Set up delegation to inheritance controller
await setEIP7702Delegation(eoaAddress, controllerAddress);
```

### Requirements
- **Access to EOA's private key** OR
- **Pre-signed delegation authorization** OR  
- **Social recovery mechanism** with delegation authority

### Challenges
❌ **Private key access**: Requires access to the original EOA's private key  
❌ **Complex setup**: Additional steps after inheritance claiming  
❌ **Timing issues**: Delay between claiming and gaining control  
❌ **Security risks**: Need to handle private keys during inheritance  

## 🔒 Security Comparison

| Aspect | Setup Phase | Post-Inheritance |
|--------|-------------|------------------|
| **Private Key Exposure** | ✅ Minimal (during setup only) | ❌ Required during inheritance |
| **Immediate Access** | ✅ Yes, after claiming | ❌ No, requires additional setup |
| **Complexity** | ✅ Simple, one-time setup | ❌ Multi-step process |
| **Security Model** | ✅ Controller-enforced | ⚠️ Depends on key management |

## 🛠️ Implementation Examples

### Setup Phase Delegation

```solidity
contract InheritanceSetup {
    function setupCompleteInheritance(
        address eoaAddress,
        address inheritorAddress,
        uint256 inactivityPeriod,
        address controllerAddress
    ) external {
        // Configure inheritance
        inheritanceManager.configureInheritance(
            eoaAddress,
            inheritorAddress,
            inactivityPeriod
        );
        
        // Set up delegation immediately
        setEIP7702Delegation(eoaAddress, controllerAddress);
    }
}
```

### Post-Inheritance Delegation

```solidity
contract PostInheritanceSetup {
    function claimAndSetupDelegation(
        address eoaAddress,
        bytes32 stateRoot,
        bytes32 blockHash,
        AccountStateProof calldata proof,
        address controllerAddress
    ) external {
        // Claim inheritance first
        inheritanceManager.claimInheritanceWithProof(
            eoaAddress,
            block.number,
            blockhash(block.number - 1),
            proof
        );
        
        // Then set up delegation (requires EOA private key access)
        setEIP7702Delegation(eoaAddress, controllerAddress);
    }
}
```

## 📋 Best Practices

### For Setup Phase Delegation
1. **Verify controller address** before delegation
2. **Test with small amounts** first
3. **Document the setup** for inheritors
4. **Use secure key management** during setup

### For Post-Inheritance Delegation
1. **Prepare delegation authorization** in advance
2. **Use secure channels** for private key handling
3. **Minimize exposure time** of private keys
4. **Consider social recovery** mechanisms

## 🎯 Recommendations

### For Most Users: Setup Phase Delegation
- **Easier to implement** and manage
- **More secure** overall approach
- **Better user experience** for inheritors
- **Recommended by the EtherSafe team**

### For Advanced Users: Post-Inheritance Delegation
- Only when setup phase delegation isn't feasible
- Requires careful security planning
- Consider the additional complexity and risks

## 🔗 Related Documentation

- [Architecture Guide](./docs/architecture.md) - Technical design details
- [Security Guide](./docs/security.md) - Security considerations
- [API Reference](./docs/api-reference.md) - Function documentation
- [Examples](./docs/examples.md) - Usage patterns

---

**The setup phase delegation approach is recommended for most users as it provides the best balance of security, simplicity, and user experience.**
