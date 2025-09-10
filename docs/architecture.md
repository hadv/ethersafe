# Architecture

This document describes the technical architecture of the EtherSafe inheritance system.

## Design Principles

### 1. Trustless Operation
- No reliance on centralized services or oracles
- All verification happens on-chain using cryptographic proofs
- State verification uses current block's state root and blockhash

### 2. EIP-7702 Integration
- Inheritors gain direct control of the original EOA
- No asset transfers needed - inheritor becomes the EOA controller
- Compatible with existing EIP-7702 infrastructure

### 3. Flexible Architecture
- Inheritance setup is separate from daily EOA operations
- EOAs can use any existing wallet or delegator during normal operations
- Delegation to inheritance controller only happens after inheritance is claimed

## Core Components

### InheritanceManager

The core contract that manages inheritance configurations and claims.

**Key Responsibilities:**
- Store inheritance configurations (inheritor, inactivity period)
- Track account activity through nonce and balance monitoring
- Verify inactivity using on-chain state proofs
- Manage inheritance claims and access control

**State Management:**
```solidity
struct InheritanceConfig {
    address inheritor;           // Who will inherit
    uint256 inactivityPeriod;   // Required inactivity duration
    bool claimed;               // Whether inheritance was claimed
}

struct ActivityRecord {
    uint256 startNonce;         // Account nonce when inactivity started
    uint256 startBalance;       // Account balance when inactivity started
    uint256 inactivityStart;    // Timestamp when inactivity was marked
    bytes32 stateRoot;          // State root when inactivity was marked
    bytes32 blockHash;          // Block hash when inactivity was marked
}
```

### EIP7702InheritanceController

The EIP-7702 delegation target that enables inheritors to control inherited EOAs.

**Key Responsibilities:**
- Verify inheritance has been claimed before allowing execution
- Ensure only the designated inheritor can control the EOA
- Execute arbitrary transactions from the inherited EOA
- Support both single and batch transaction execution

**Access Control:**
```solidity
function execute(address to, uint256 value, bytes calldata data) external {
    // 1. Verify inheritance is claimed
    require(inheritanceManager.isInheritanceClaimed(address(this)), "Inheritance not claimed");
    
    // 2. Verify caller is the inheritor
    (address inheritor,,) = inheritanceManager.getInheritanceConfig(address(this));
    require(msg.sender == inheritor, "Not the inheritor");
    
    // 3. Execute transaction from EOA
    (bool success, bytes memory result) = to.call{value: value}(data);
    require(success, "Execution failed");
}
```

## Inheritance Flow

### Phase 1: Setup
1. EOA owner calls `configureInheritance()`
2. System stores inheritance configuration
3. EOA continues normal operations using any existing wallet/delegator

### Phase 2: Inactivity Detection
1. Anyone can call `markInactivityStart()` when they notice an account is inactive
2. System verifies current account state (nonce, balance) using state proofs
3. Inactivity period countdown begins

### Phase 3: Inheritance Claim
1. After inactivity period expires, inheritor calls `claimInheritance()`
2. System verifies account remained inactive (no nonce/balance changes)
3. Inheritance is granted to the inheritor

### Phase 4: EOA Control

**Option A: Pre-Setup Delegation (Recommended)**
1. EOA owner sets up EIP-7702 delegation during initial setup
2. EOA delegates to `EIP7702InheritanceController` immediately
3. Controller only allows inheritor access after inheritance is claimed
4. More secure and practical approach

**Option B: Post-Inheritance Delegation**
1. EOA sets up EIP-7702 delegation after inheritance is claimed
2. Requires access to EOA's private key or pre-signed authorization
3. Less practical but possible for specific scenarios

In both cases:
- Inheritor can execute transactions directly from the inherited EOA
- All assets remain in the original EOA address
- Controller enforces inheritance verification

## State Verification

### Activity Detection
The system detects account activity by monitoring:
- **Nonce changes**: Any transaction sent by the account owner increases the account nonce

**Important**: The system **only** checks nonce changes, not balance changes. This is because:
- Balance can increase without account owner activity (receiving transfers, mining rewards, airdrops)
- Only nonce changes indicate that the account owner has sent a transaction
- This prevents false positives where inactive accounts receive funds

```solidity
function isAccountActive(address account, ActivityRecord memory record) internal view returns (bool) {
    uint256 currentNonce = account.nonce;

    // Only check nonce - balance can change without owner activity
    return currentNonce != record.startNonce;
}
```

### State Proof Verification
The system now implements complete Merkle proof verification for account state:

```solidity
struct AccountStateProof {
    uint256 nonce;              // Account nonce
    uint256 balance;            // Account balance
    bytes32 storageHash;        // Storage trie root hash
    bytes32 codeHash;           // Code hash
    bytes32[] proof;            // Merkle proof path
}

function verifyAccountState(
    address account,
    bytes32 stateRoot,
    AccountStateProof memory accountStateProof
) public pure returns (bool) {
    // Encode account state according to Ethereum's account encoding
    bytes memory accountData = abi.encodePacked(
        accountStateProof.nonce,
        accountStateProof.balance,
        accountStateProof.storageHash,
        accountStateProof.codeHash
    );

    // Hash the account data
    bytes32 accountHash = keccak256(accountData);

    // Create the leaf for the state trie
    bytes32 leaf = keccak256(abi.encodePacked(account, accountHash));

    // Verify the Merkle proof using OpenZeppelin's MerkleProof library
    return MerkleProof.verify(accountStateProof.proof, stateRoot, leaf);
}
```

### Block Hash Verification
The system also verifies block hashes to ensure state proofs are from valid blocks:

```solidity
function verifyBlockHash(
    uint256 blockNumber,
    bytes32 providedBlockHash
) public view returns (bool) {
    // Verify the provided block hash matches the actual block hash
    // Handles edge cases for current blocks and blocks older than 256
    return blockhash(blockNumber) == providedBlockHash;
}
```

## Security Considerations

### Access Control
- Only EOA owners can configure inheritance
- Only designated inheritors can claim inheritance
- Only verified inheritors can control inherited EOAs

### State Integrity
- All state changes are verified using cryptographic proofs
- Inactivity detection uses multiple verification layers
- State root and block hash validation prevents manipulation

### EIP-7702 Safety
- Delegation only happens after inheritance is properly claimed
- Controller contract has strict access controls
- All transactions require inheritor authorization

## Deployment Architecture

### Single Network Deployment
```
InheritanceManager (singleton)
    ↓
EIP7702InheritanceController (singleton)
    ↓
Multiple EOAs can use the same controller instance
```

### Multi-Network Support
Each network requires its own deployment of both contracts, but the same inheritor can inherit EOAs across multiple networks.

## Gas Optimization

### Efficient Storage
- Use packed structs to minimize storage slots
- Immutable variables for contract addresses
- Minimal state changes during normal operations

### Batch Operations
- Support batch transaction execution
- Reduce gas costs for multiple operations
- Optimize for common inheritance scenarios

## Extensibility

### Modular Design
- Core inheritance logic is separate from EIP-7702 implementation
- Easy to add new delegation mechanisms
- Support for different proof systems

### Upgrade Path
- Contracts are designed to be immutable for security
- New features can be added through new contract deployments
- Backward compatibility maintained through interface stability
