// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {InheritanceManager} from "../src/InheritanceManager.sol";
import {EIP7702InheritanceController} from "../src/EIP7702InheritanceController.sol";

/**
 * @title Deploy Script for EtherSafe Inheritance System
 * @dev Deploys InheritanceManager and EIP7702InheritanceController contracts
 *
 * Usage:
 * forge script script/Deploy.s.sol:DeployScript --rpc-url <RPC_URL> --private-key <PRIVATE_KEY> --broadcast --verify
 *
 * Or with environment variables:
 * forge script script/Deploy.s.sol:DeployScript --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
 */
contract DeployScript is Script {
    // Deployment addresses will be stored here
    InheritanceManager public inheritanceManager;
    EIP7702InheritanceController public controller;

    function run() external {
        // Get deployer private key from environment or command line
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying EtherSafe Inheritance System...");
        console.log("Deployer address:", vm.addr(deployerPrivateKey));
        console.log("Chain ID:", block.chainid);

        // Deploy InheritanceManager first
        console.log("\n1. Deploying InheritanceManager...");
        inheritanceManager = new InheritanceManager();
        console.log("InheritanceManager deployed at:", address(inheritanceManager));

        // Deploy EIP7702InheritanceController
        console.log("\n2. Deploying EIP7702InheritanceController...");
        controller = new EIP7702InheritanceController(address(inheritanceManager));
        console.log("EIP7702InheritanceController deployed at:", address(controller));

        // Verify the deployment
        console.log("\n3. Verifying deployment...");
        require(
            controller.inheritanceManager() == inheritanceManager,
            "Controller not properly linked to InheritanceManager"
        );
        console.log("Deployment verification successful!");

        vm.stopBroadcast();

        // Print deployment summary
        printDeploymentSummary();
    }

    function printDeploymentSummary() internal view {
        console.log("\n" "========================================");
        console.log("EtherSafe Deployment Complete!");
        console.log("========================================");
        console.log("Network:", getNetworkName());
        console.log("Chain ID:", block.chainid);
        console.log("");
        console.log("Contract Addresses:");
        console.log("InheritanceManager:          ", address(inheritanceManager));
        console.log("EIP7702InheritanceController:", address(controller));
        console.log("");
        console.log("Next Steps:");
        console.log("1. Verify contracts on block explorer");
        console.log("2. Update frontend/docs with new addresses");
        console.log("3. Test inheritance configuration");
        console.log("");
        console.log("Usage Example:");
        console.log("// Configure inheritance");
        console.log("inheritanceManager.configureInheritance(");
        console.log("    eoaAddress,");
        console.log("    inheritorAddress,");
        console.log("    365 days");
        console.log(");");
        console.log("========================================");
    }

    function getNetworkName() internal view returns (string memory) {
        uint256 chainId = block.chainid;

        if (chainId == 1) return "Ethereum Mainnet";
        if (chainId == 11155111) return "Sepolia Testnet";
        if (chainId == 17000) return "Holesky Testnet";
        if (chainId == 137) return "Polygon Mainnet";
        if (chainId == 80001) return "Polygon Mumbai";
        if (chainId == 10) return "Optimism Mainnet";
        if (chainId == 11155420) return "Optimism Sepolia";
        if (chainId == 42161) return "Arbitrum One";
        if (chainId == 421614) return "Arbitrum Sepolia";
        if (chainId == 8453) return "Base Mainnet";
        if (chainId == 84532) return "Base Sepolia";
        if (chainId == 31337) return "Local Anvil";

        return "Unknown Network";
    }
}

/**
 * @title Deployment Configuration
 * @dev Helper contract for managing deployment configurations across networks
 */
contract DeploymentConfig {
    struct NetworkConfig {
        string name;
        bool isTestnet;
        uint256 minInactivityPeriod;
    }

    mapping(uint256 => NetworkConfig) public networkConfigs;

    constructor() {
        // Mainnet configurations
        networkConfigs[1] = NetworkConfig("Ethereum Mainnet", false, 30 days);
        networkConfigs[137] = NetworkConfig("Polygon Mainnet", false, 30 days);
        networkConfigs[10] = NetworkConfig("Optimism Mainnet", false, 30 days);
        networkConfigs[42161] = NetworkConfig("Arbitrum One", false, 30 days);
        networkConfigs[8453] = NetworkConfig("Base Mainnet", false, 30 days);

        // Testnet configurations (shorter periods for testing)
        networkConfigs[11155111] = NetworkConfig("Sepolia Testnet", true, 1 hours);
        networkConfigs[17000] = NetworkConfig("Holesky Testnet", true, 1 hours);
        networkConfigs[80001] = NetworkConfig("Polygon Mumbai", true, 1 hours);
        networkConfigs[11155420] = NetworkConfig("Optimism Sepolia", true, 1 hours);
        networkConfigs[421614] = NetworkConfig("Arbitrum Sepolia", true, 1 hours);
        networkConfigs[84532] = NetworkConfig("Base Sepolia", true, 1 hours);

        // Local development
        networkConfigs[31337] = NetworkConfig("Local Anvil", true, 1 minutes);
    }

    function getNetworkConfig(uint256 chainId) external view returns (NetworkConfig memory) {
        return networkConfigs[chainId];
    }
}
