# EtherSafe - EIP-7702 Inheritance System

A trustless inheritance system for Ethereum EOAs (Externally Owned Accounts) using EIP-7702 delegation.

## Overview

EtherSafe enables EOA owners to set up inheritance that automatically transfers control to designated inheritors after a period of account inactivity. The system uses on-chain state verification and EIP-7702 delegation to provide a trustless, decentralized inheritance mechanism.

## Key Features

- ✅ **Trustless**: No reliance on centralized services or oracles
- ✅ **On-chain Verification**: Uses current state root and blockhash for inactivity detection
- ✅ **EIP-7702 Integration**: Inheritors gain direct control of the original EOA
- ✅ **Flexible**: Works with any existing EIP-7702 setup
- ✅ **Secure**: Multiple verification layers and access controls

## Architecture

### Core Components

1. **InheritanceManager** - Core inheritance logic and state management
2. **EIP7702InheritanceController** - EIP-7702 delegation target for inherited EOAs

### Inheritance Flow

```
1. Setup Phase
   ├── EOA owner configures inheritance
   ├── Specifies inheritor and inactivity period
   └── EOA continues normal operations

2. Inactivity Detection
   ├── Anyone can mark inactivity start
   ├── System verifies account state hasn't changed
   └── Inactivity period countdown begins

3. Inheritance Claim
   ├── Inheritor claims inheritance after period expires
   ├── System verifies account remained inactive
   └── Inheritance is granted

4. EOA Control Transfer
   ├── EOA delegates to EIP7702InheritanceController
   ├── Inheritor gains direct control of EOA
   └── All assets remain in original EOA
```

## Quick Start

See [Getting Started Guide](./getting-started.md) for detailed setup instructions.

## Documentation

- [Getting Started](./getting-started.md) - Setup and basic usage
- [Architecture](./architecture.md) - Technical design and components
- [API Reference](./api-reference.md) - Contract interfaces and functions
- [Examples](./examples.md) - Usage examples and patterns
- [Security](./security.md) - Security considerations and best practices

## Repository Structure

```
src/
├── InheritanceManager.sol          # Core inheritance logic
└── EIP7702InheritanceController.sol # EIP-7702 delegation controller

test/
├── InheritanceManager.t.sol        # Core logic tests
└── EOAInheritanceViaEIP7702.t.sol  # Integration tests

examples/
└── EOAInheritanceViaEIP7702.sol    # Usage examples

docs/
├── README.md                       # This file
├── getting-started.md              # Setup guide
├── architecture.md                 # Technical details
├── api-reference.md                # Contract APIs
├── examples.md                     # Usage patterns
└── security.md                     # Security guide
```

## License

MIT License - see LICENSE file for details.
