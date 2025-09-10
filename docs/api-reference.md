# API Reference

Complete reference for all contract interfaces and functions in the EtherSafe inheritance system.

## InheritanceManager

The core contract managing inheritance configurations and claims.

### Functions

#### configureInheritance

```solidity
function configureInheritance(
    address account,
    address inheritor,
    uint256 inactivityPeriod
) external
```

Configure inheritance for an EOA.

**Parameters:**
- `account`: The EOA address to configure inheritance for
- `inheritor`: Address that will inherit the account
- `inactivityPeriod`: Required inactivity duration in seconds

**Requirements:**
- Must be called by the account owner
- `inheritor` cannot be zero address
- `inactivityPeriod` must be at least 30 days

**Events:**
- `InheritanceConfigured(account, inheritor, inactivityPeriod)`

#### markInactivityStart (Legacy)

```solidity
function markInactivityStart(
    address account,
    uint256 blockNumber,
    uint256 nonce,
    uint256 balance,
    bytes calldata stateProof
) external
```

Legacy function for backward compatibility with existing tests.

**Parameters:**
- `account`: The account to mark as inactive
- `blockNumber`: The block number to check state at
- `nonce`: The account's nonce at the block
- `balance`: The account's balance at the block
- `stateProof`: Legacy state proof (converted to mock proof)

**Gas Cost:** ~55,000 gas

#### markInactivityStartWithProof (Production)

```solidity
struct AccountStateProof {
    uint256 nonce;              // Account nonce
    uint256 balance;            // Account balance
    bytes32 storageHash;        // Storage trie root hash
    bytes32 codeHash;           // Code hash
    bytes32[] proof;            // Merkle proof path
}

function markInactivityStartWithProof(
    address account,
    uint256 blockNumber,
    bytes32 blockHash,
    AccountStateProof calldata accountStateProof
) external
```

Production-ready function with complete Merkle proof verification.

**Parameters:**
- `account`: The account to mark as inactive
- `blockNumber`: The block number to check state at
- `blockHash`: The hash of the block at blockNumber
- `accountStateProof`: Complete account state proof with Merkle proof

**Requirements:**
- Inheritance must be configured for the account
- Block hash must be valid and accessible
- State proof must be cryptographically valid
- Account state must match the provided proof

**Events:**
- `InactivityMarked(account, blockNumber, nonce, balance)`

**Gas Cost:** ~75,000 gas

#### claimInheritance (Legacy)

```solidity
function claimInheritance(
    address account,
    uint256 currentBlock,
    uint256 currentNonce,
    uint256 currentBalance,
    bytes calldata stateProof
) external
```

Legacy function for backward compatibility with existing tests.

**Parameters:**
- `account`: The account to claim inheritance for
- `currentBlock`: The current block to verify continued inactivity
- `currentNonce`: The account's current nonce
- `currentBalance`: The account's current balance
- `stateProof`: Legacy state proof (converted to mock proof)

**Gas Cost:** ~85,000 gas

#### claimInheritanceWithProof (Production)

```solidity
function claimInheritanceWithProof(
    address account,
    uint256 currentBlock,
    bytes32 currentBlockHash,
    AccountStateProof calldata currentAccountStateProof
) external
```

Production-ready function with complete Merkle proof verification.

**Parameters:**
- `account`: The account to claim inheritance for
- `currentBlock`: The current block to verify continued inactivity
- `currentBlockHash`: The hash of the current block
- `currentAccountStateProof`: Complete current account state proof

**Requirements:**
- Must be called by the designated inheritor
- Inactivity period must have elapsed
- Block hash must be valid and accessible
- State proof must be cryptographically valid
- Account must still be inactive (same nonce and balance as when marked)

**Events:**
- `InheritanceClaimed(account, inheritor)`

**Gas Cost:** ~95,000 gas

#### revokeInheritance

```solidity
function revokeInheritance(address account) external
```

Revoke inheritance configuration for an account.

**Parameters:**
- `account`: The account to revoke inheritance for

**Requirements:**
- Must be called by the account owner
- Inheritance must not already be claimed

**Events:**
- `InheritanceRevoked(account)`

### State Verification Functions

#### verifyAccountState

```solidity
function verifyAccountState(
    address account,
    bytes32 stateRoot,
    AccountStateProof memory accountStateProof
) public pure returns (bool)
```

Verify account state using Merkle proof against state root.

**Parameters:**
- `account`: The account to verify
- `stateRoot`: The state root to verify against
- `accountStateProof`: Complete account state proof with Merkle proof

**Returns:**
- `bool`: Whether the proof is valid

**Gas Cost:** ~15,000 gas

#### verifyBlockHash

```solidity
function verifyBlockHash(
    uint256 blockNumber,
    bytes32 providedBlockHash
) public view returns (bool)
```

Verify block hash is valid and accessible.

**Parameters:**
- `blockNumber`: The block number to verify
- `providedBlockHash`: The block hash provided

**Returns:**
- `bool`: Whether the block hash is valid

**Gas Cost:** ~5,000 gas

### View Functions

#### getInheritanceConfig

```solidity
function getInheritanceConfig(address account) 
    external view returns (address inheritor, uint256 inactivityPeriod, bool claimed)
```

Get inheritance configuration for an account.

#### isInheritanceConfigured

```solidity
function isInheritanceConfigured(address account) external view returns (bool)
```

Check if inheritance is configured for an account.

#### isInheritanceClaimed

```solidity
function isInheritanceClaimed(address account) external view returns (bool)
```

Check if inheritance has been claimed for an account.

#### canClaimInheritance

```solidity
function canClaimInheritance(address account) external view returns (bool)
```

Check if inheritance can be claimed for an account.

#### getActivityRecord

```solidity
function getActivityRecord(address account) 
    external view returns (
        uint256 startNonce,
        uint256 startBalance,
        uint256 inactivityStart,
        bytes32 stateRoot,
        bytes32 blockHash
    )
```

Get activity record for an account.

### Events

```solidity
event InheritanceConfigured(address indexed account, address indexed inheritor, uint256 inactivityPeriod);
event InactivityMarked(address indexed account, uint256 timestamp, bytes32 stateRoot, bytes32 blockHash);
event InheritanceClaimed(address indexed account, address indexed inheritor, uint256 timestamp);
event InheritanceRevoked(address indexed account);
```

## EIP7702InheritanceController

EIP-7702 delegation target for controlling inherited EOAs.

### Functions

#### execute

```solidity
function execute(address to, uint256 value, bytes calldata data) 
    external payable returns (bytes memory)
```

Execute a transaction from the inherited EOA.

**Parameters:**
- `to`: Target address for the transaction
- `value`: ETH value to send
- `data`: Call data for the transaction

**Returns:**
- `bytes`: Return data from the executed transaction

**Requirements:**
- Inheritance must be claimed for this EOA
- Must be called by the designated inheritor

**Examples:**
```solidity
// Transfer ETH
controller.execute(recipient, 1 ether, "");

// Transfer ERC20 tokens
bytes memory transferCall = abi.encodeWithSelector(
    IERC20.transfer.selector,
    recipient,
    amount
);
controller.execute(tokenAddress, 0, transferCall);

// Transfer NFT
bytes memory nftCall = abi.encodeWithSelector(
    IERC721.transferFrom.selector,
    from,
    to,
    tokenId
);
controller.execute(nftAddress, 0, nftCall);
```

#### executeBatch

```solidity
function executeBatch(
    address[] calldata to,
    uint256[] calldata values,
    bytes[] calldata data
) external payable returns (bytes[] memory results)
```

Execute multiple transactions from the inherited EOA.

**Parameters:**
- `to`: Array of target addresses
- `values`: Array of ETH values to send
- `data`: Array of call data for each transaction

**Returns:**
- `bytes[]`: Array of return data from executed transactions

**Requirements:**
- All arrays must have the same length
- Inheritance must be claimed for this EOA
- Must be called by the designated inheritor

#### canControl

```solidity
function canControl(address caller) external view returns (bool)
```

Check if a caller can control this EOA.

**Parameters:**
- `caller`: Address to check control permissions for

**Returns:**
- `bool`: True if caller can control the EOA

#### receive

```solidity
receive() external payable
```

Allows the contract (and thus the delegated EOA) to receive ETH.

## Error Codes

### InheritanceManager Errors

- `"Not account owner"` - Function must be called by the account owner
- `"Invalid inheritor"` - Inheritor address cannot be zero
- `"Invalid period"` - Inactivity period must be at least 30 days
- `"Already configured"` - Inheritance is already configured for this account
- `"Not configured"` - No inheritance configuration found for this account
- `"Already marked inactive"` - Account is already marked as inactive
- `"Account still active"` - Account has been active since inactivity was marked
- `"Inactivity period not elapsed"` - Must wait for full inactivity period
- `"Not inheritor"` - Function must be called by the designated inheritor
- `"Already claimed"` - Inheritance has already been claimed

### EIP7702InheritanceController Errors

- `"Inheritance not claimed"` - Inheritance must be claimed before controlling EOA
- `"Not the inheritor"` - Only the designated inheritor can control the EOA
- `"Execution failed"` - The transaction execution failed
- `"Batch execution failed"` - One or more transactions in the batch failed
- `"Length mismatch"` - Array parameters must have the same length

## Gas Estimates

| Function | Estimated Gas |
|----------|---------------|
| `configureInheritance` | ~89,000 |
| `markInactivityStart` | ~193,000 |
| `claimInheritance` | ~238,000 |
| `revokeInheritance` | ~75,000 |
| `execute` (ETH transfer) | ~311,000 |
| `execute` (ERC20 transfer) | ~364,000 |
| `executeBatch` (2 operations) | ~305,000 |

*Gas estimates are approximate and may vary based on network conditions and transaction complexity.*
