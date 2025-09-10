# EtherSafe Deployment Guide

This guide covers deploying the EtherSafe inheritance system to various networks.

## Prerequisites

1. **Foundry installed**:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. **Environment setup**:
```bash
# Copy environment template
cp .env.example .env

# Edit .env with your values
PRIVATE_KEY=your_private_key_here
RPC_URL=your_rpc_url_here
ETHERSCAN_API_KEY=your_etherscan_api_key_here
```

3. **Install dependencies**:
```bash
forge install
```

## Quick Deployment

### Local Development (Anvil)

1. **Start local node**:
```bash
anvil
```

2. **Deploy contracts**:
```bash
forge script script/Deploy.s.sol:DeployScript --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast
```

### Testnet Deployment (Sepolia)

```bash
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://sepolia.infura.io/v3/YOUR_INFURA_KEY \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

### Mainnet Deployment

```bash
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://mainnet.infura.io/v3/YOUR_INFURA_KEY \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

## Network-Specific Deployments

### Ethereum Networks

```bash
# Sepolia Testnet
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://sepolia.infura.io/v3/YOUR_KEY \
  --broadcast --verify

# Holesky Testnet  
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://holesky.infura.io/v3/YOUR_KEY \
  --broadcast --verify

# Ethereum Mainnet
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://mainnet.infura.io/v3/YOUR_KEY \
  --broadcast --verify
```

### Layer 2 Networks

```bash
# Polygon Mumbai Testnet
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://polygon-mumbai.infura.io/v3/YOUR_KEY \
  --broadcast --verify

# Polygon Mainnet
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://polygon-mainnet.infura.io/v3/YOUR_KEY \
  --broadcast --verify

# Optimism Sepolia
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://optimism-sepolia.infura.io/v3/YOUR_KEY \
  --broadcast --verify

# Optimism Mainnet
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://optimism-mainnet.infura.io/v3/YOUR_KEY \
  --broadcast --verify

# Arbitrum Sepolia
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://arbitrum-sepolia.infura.io/v3/YOUR_KEY \
  --broadcast --verify

# Arbitrum One
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://arbitrum-mainnet.infura.io/v3/YOUR_KEY \
  --broadcast --verify

# Base Sepolia
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://base-sepolia.infura.io/v3/YOUR_KEY \
  --broadcast --verify

# Base Mainnet
forge script script/Deploy.s.sol:DeployScript \
  --rpc-url https://base-mainnet.infura.io/v3/YOUR_KEY \
  --broadcast --verify
```

## Environment Variables

Create a `.env` file:

```bash
# Required
PRIVATE_KEY=0x1234567890abcdef...
RPC_URL=https://your-rpc-endpoint

# Optional (for contract verification)
ETHERSCAN_API_KEY=your_etherscan_api_key
POLYGONSCAN_API_KEY=your_polygonscan_api_key
OPTIMISTIC_ETHERSCAN_API_KEY=your_optimistic_etherscan_api_key
ARBISCAN_API_KEY=your_arbiscan_api_key
BASESCAN_API_KEY=your_basescan_api_key
```

## Post-Deployment Steps

### 1. Verify Deployment

```bash
# Check contract addresses
forge script script/Deploy.s.sol:DeployScript --rpc-url $RPC_URL

# Verify on block explorer (if not done during deployment)
forge verify-contract <CONTRACT_ADDRESS> src/InheritanceManager.sol:InheritanceManager --etherscan-api-key $ETHERSCAN_API_KEY
forge verify-contract <CONTROLLER_ADDRESS> src/EIP7702InheritanceController.sol:EIP7702InheritanceController --constructor-args $(cast abi-encode "constructor(address)" <MANAGER_ADDRESS>) --etherscan-api-key $ETHERSCAN_API_KEY
```

### 2. Test Deployment

```bash
# Run integration tests against deployed contracts
forge test --fork-url $RPC_URL -vv
```

### 3. Update Documentation

Update the deployed contract addresses in:
- `docs/getting-started.md`
- Frontend configuration files
- Integration examples

## Deployment Costs

Estimated gas costs for deployment:

| Network | InheritanceManager | EIP7702InheritanceController | Total ETH (at 20 gwei) |
|---------|-------------------|------------------------------|-------------------------|
| Ethereum | ~1,200,000 gas | ~800,000 gas | ~0.04 ETH |
| Polygon | ~1,200,000 gas | ~800,000 gas | ~0.002 MATIC |
| Optimism | ~1,200,000 gas | ~800,000 gas | ~0.0004 ETH |
| Arbitrum | ~1,200,000 gas | ~800,000 gas | ~0.0004 ETH |
| Base | ~1,200,000 gas | ~800,000 gas | ~0.0004 ETH |

## Troubleshooting

### Common Issues

1. **Insufficient funds**: Ensure deployer account has enough native tokens
2. **RPC rate limits**: Use premium RPC endpoints for mainnet deployments
3. **Verification failures**: Check API keys and contract addresses

### Debug Commands

```bash
# Check deployer balance
cast balance $DEPLOYER_ADDRESS --rpc-url $RPC_URL

# Estimate deployment gas
forge script script/Deploy.s.sol:DeployScript --rpc-url $RPC_URL --gas-estimate

# Dry run deployment
forge script script/Deploy.s.sol:DeployScript --rpc-url $RPC_URL
```

## Security Checklist

Before mainnet deployment:

- [ ] Audit smart contracts
- [ ] Test on testnets
- [ ] Verify contract source code
- [ ] Check deployer permissions
- [ ] Review gas optimizations
- [ ] Prepare incident response plan

## Support

For deployment issues:
- Check [GitHub Issues](https://github.com/hadv/ethersafe/issues)
- Review [Documentation](./docs/)
- Contact team via [Discord/Telegram]
