# EOA Inheritance Logic - EIP-7702 Implementation

This project implements an enhanced version of the EOA inheritance mechanism proposed in [EIP-7702 discussion](https://ethereum-magicians.org/t/eoa-inheritance-over-inactivity-with-eip-7702/25382).

## Overview

The `EOAInheritanceLogic` contract enables Externally Owned Accounts (EOAs) to set up inheritance mechanisms that activate after periods of inactivity. Using EIP-7702, an EOA can delegate its execution to this contract logic while maintaining its private key ownership.

## Key Features

### Enhanced Security
- **Reentrancy Protection**: All state-changing functions are protected against reentrancy attacks
- **Input Validation**: Comprehensive validation of all parameters
- **Grace Period**: Additional safety period after inactivity period before inheritance can be claimed
- **Emergency Reset**: Allows the EOA to reset all inheritance settings in edge cases

### Flexible Configuration
- **Configurable Periods**: Inactivity periods between 30 days and 10 years
- **Updatable Settings**: Owner can update inheritance configuration at any time
- **Cancellation**: Owner can cancel inheritance at any time

### Comprehensive Monitoring
- **Activity Tracking**: Automatic tracking of last activity timestamp
- **Status Queries**: Functions to check inheritance status and remaining time
- **Event Logging**: Comprehensive event emission for all major actions

## Contract Architecture

### Storage Layout
The contract uses deterministic storage slots to store state directly in the EOA's storage:

```solidity
bytes32 constant INHERITOR_SLOT = keccak256("eip7702.inheritance.inheritor");
bytes32 constant PERIOD_SLOT = keccak256("eip7702.inheritance.period");
bytes32 constant LAST_ACTIVE_SLOT = keccak256("eip7702.inheritance.last_active_timestamp");
bytes32 constant AUTHORIZED_OWNER_SLOT = keccak256("eip7702.inheritance.authorized_owner");
bytes32 constant REENTRANCY_GUARD_SLOT = keccak256("eip7702.inheritance.reentrancy_guard");
bytes32 constant GRACE_PERIOD_SLOT = keccak256("eip7702.inheritance.grace_period");
```

### Main Functions

#### `setupInheritance(address _inheritor, uint256 _inactivityPeriod)`
- Sets up or updates inheritance configuration
- Validates inheritor address and inactivity period
- Updates last activity timestamp

#### `keepAlive()`
- Resets the inactivity timer
- Must be called by the authorized owner to prove continued activity

#### `claimOwnership()`
- Allows the inheritor to claim ownership after inactivity + grace period
- Transfers authorized ownership to the inheritor
- Clears inheritance configuration

#### `cancelInheritance()`
- Allows the owner to cancel inheritance configuration
- Resets last activity timestamp

#### `emergencyReset()`
- Emergency function to reset all inheritance settings
- Can only be called by the current authorized owner

### View Functions

#### `getInheritanceConfig()`
Returns current inheritance configuration including inheritor, periods, and timestamps.

#### `canClaimInheritance()`
Checks if inheritance can be claimed and returns remaining time if not.

#### `getAuthorizedOwner()`
Returns the current authorized owner address.

## EOAController - Extended Functionality

The `EOAController` contract extends `EOAInheritanceLogic` with additional functionality for comprehensive EOA control:

### Transaction Management
- **`executeTransaction()`**: Execute single transactions from the EOA
- **`executeBatchTransactions()`**: Execute multiple transactions in a batch
- **`transferETH()`**: Transfer ETH from the EOA
- **`transferERC20()`**: Transfer ERC20 tokens from the EOA
- **`approveERC20()`**: Approve ERC20 token spending from the EOA

### Asset Management
- **`getETHBalance()`**: Get the current ETH balance of the EOA
- **`getERC20Balance()`**: Get the current ERC20 token balance of the EOA
- **`emergencyWithdraw()`**: Emergency withdrawal of all ETH
- **`canExecuteTransaction()`**: Check if a transaction can be executed

### How EIP-7702 Delegation Works

With EIP-7702, an EOA can delegate its execution to a smart contract while retaining its private key. This enables:

1. **EOA Delegation**: The EOA signs a delegation authorization to the inheritance contract
2. **Logic Execution**: When the EOA is called, it executes the delegated contract's logic
3. **State Storage**: The contract logic operates on the EOA's storage directly
4. **Asset Control**: The inheritor can control EOA assets through the delegated logic

### Real-World Usage Flow

```solidity
// 1. EOA owner delegates to EOAController and sets up inheritance
vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
vm.prank(eoaOwner);
EOAController(eoaOwner).setupInheritance(inheritor, 60 days);

// 2. After inactivity period, inheritor claims ownership
vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
vm.prank(inheritor);
EOAController(eoaOwner).claimOwnership();

// 3. Inheritor can now control EOA assets via delegation
vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
vm.prank(inheritor);
EOAController(eoaOwner).transferETH(payable(recipient), 1 ether);

// 4. Transfer ERC20 tokens from EOA
vm.prank(inheritor);
EOAController(eoaOwner).transferERC20(tokenAddress, recipient, amount);

// 5. Execute arbitrary transactions from EOA
bytes memory data = abi.encodeWithSignature("someFunction(uint256)", 123);
vm.prank(inheritor);
EOAController(eoaOwner).executeTransaction(targetContract, value, data);
```

**Key Point**: The inheritor doesn't get the EOA's private key. Instead, they control the EOA through the delegated contract logic, which provides secure and programmable asset management.

## Improvements Over Original Design

1. **Enhanced Security**:
   - Added reentrancy protection
   - Comprehensive input validation
   - Grace period mechanism

2. **Better Error Handling**:
   - Custom error types for gas efficiency
   - Clear error messages for different failure scenarios

3. **Comprehensive Events**:
   - Events for all major state changes
   - Better tracking and monitoring capabilities

4. **Flexible Configuration**:
   - Configurable grace periods
   - Ability to update inheritance settings
   - Emergency reset functionality

5. **Robust Testing**:
   - 25 comprehensive unit tests
   - Edge case coverage
   - Integration test scenarios

## Usage Example

```solidity
// 1. Setup inheritance (60 days inactivity period)
inheritanceLogic.setupInheritance(inheritorAddress, 60 days);

// 2. Stay active by calling keepAlive periodically
inheritanceLogic.keepAlive();

// 3. After inactivity period + grace period, inheritor can claim
inheritanceLogic.claimOwnership(); // Called by inheritor

// 4. Owner can cancel inheritance at any time
inheritanceLogic.cancelInheritance();
```

## Testing

The project includes comprehensive test suites:

### Unit Tests (`EOAInheritanceLogic.t.sol`)
- 25 tests covering core inheritance logic
- Setup and configuration scenarios
- Activity tracking and keep-alive functionality
- Ownership claiming with various conditions
- Cancellation and emergency reset
- Edge cases and error conditions

### EIP-7702 Integration Tests (`EOAInheritanceEIP7702.t.sol`)
- 23 tests covering real EOA delegation scenarios
- EIP-7702 delegation using Foundry's `signAndAttachDelegation`
- EOA control transfer after inheritance claim via delegated contract logic
- Asset management (ETH and ERC20 tokens) through EOAController
- Batch transaction execution from EOA address
- Complete inheritance flow with real transactions
- Tests proving inheritor can send ETH and tokens from EOA via delegation

### Additional Components
- `EOAController.sol`: Extended functionality for EOA control
- `MockERC20.sol`: ERC20 token for testing
- `TestTarget.sol`: Contract for testing EOA interactions

Run all tests:
```bash
forge test -vv
```

Run specific test suite:
```bash
forge test --match-contract EOAInheritanceLogicTest -vv
forge test --match-contract EOAInheritanceEIP7702Test -vv
```

## Security Considerations

1. **Private Key Security**: The original EOA private key remains unchanged and secure
2. **Reentrancy Protection**: All functions are protected against reentrancy attacks
3. **Input Validation**: Comprehensive validation prevents invalid configurations
4. **Grace Period**: Additional safety period prevents accidental inheritance claims
5. **Emergency Reset**: Allows recovery from edge cases

## Deployment

Deploy using Foundry:
```bash
forge script script/EOAInheritanceLogic.s.sol --rpc-url <RPC_URL> --private-key <PRIVATE_KEY>
```

---

## Foundry Commands

### Build
```shell
forge build
```

### Test
```shell
forge test
```

### Format
```shell
forge fmt
```

### Gas Snapshots
```shell
forge snapshot
```

### Deploy
```shell
forge script script/EOAInheritanceLogic.s.sol:EOAInheritanceLogicScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```
