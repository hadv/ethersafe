// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../src/InheritanceManager.sol";

/**
 * @title EOA Inheritance via EIP-7702
 * @dev Shows how inheritor gains control of the actual EOA account via EIP-7702
 * 
 * The key insight: After inheritance is claimed, the inheritor can control the EOA
 * account directly through EIP-7702 delegation, not just call a delegator contract.
 */

/**
 * @title EIP7702InheritanceController
 * @dev This contract becomes the new delegation target for the inherited EOA
 */
contract EIP7702InheritanceController {
    
    InheritanceManager public immutable inheritanceManager;
    
    constructor(address _inheritanceManager) {
        inheritanceManager = InheritanceManager(_inheritanceManager);
    }
    
    /**
     * @notice Execute a transaction from the inherited EOA
     * @dev This function is called when the EOA delegates to this contract via EIP-7702
     * @param to Target address
     * @param value ETH value to send
     * @param data Call data
     */
    function execute(address to, uint256 value, bytes calldata data) external payable returns (bytes memory) {
        // Verify that inheritance has been claimed for this EOA
        require(inheritanceManager.isInheritanceClaimed(address(this)), "Inheritance not claimed");
        
        // Verify that the caller is the inheritor
        (address inheritor,,) = inheritanceManager.getInheritanceConfig(address(this));
        require(msg.sender == inheritor, "Not the inheritor");
        
        // Execute the transaction from the EOA (address(this) is the EOA when delegated)
        (bool success, bytes memory result) = to.call{value: value}(data);
        require(success, "Execution failed");
        
        return result;
    }
    
    /**
     * @notice Execute multiple transactions from the inherited EOA
     */
    function executeBatch(
        address[] calldata to,
        uint256[] calldata values,
        bytes[] calldata data
    ) external payable returns (bytes[] memory results) {
        require(inheritanceManager.isInheritanceClaimed(address(this)), "Inheritance not claimed");
        
        (address inheritor,,) = inheritanceManager.getInheritanceConfig(address(this));
        require(msg.sender == inheritor, "Not the inheritor");
        
        require(to.length == values.length && values.length == data.length, "Length mismatch");
        
        results = new bytes[](to.length);
        for (uint256 i = 0; i < to.length; i++) {
            (bool success, bytes memory result) = to[i].call{value: values[i]}(data[i]);
            require(success, "Batch execution failed");
            results[i] = result;
        }
        
        return results;
    }
    
    // No need for separate transfer methods!
    // The execute() function can handle all transfers:
    //
    // Transfer ETH:
    // execute(recipient, amount, "")
    //
    // Transfer ERC20:
    // execute(tokenAddress, 0, abi.encodeWithSelector(IERC20.transfer.selector, recipient, amount))
    //
    // Transfer ERC721:
    // execute(nftAddress, 0, abi.encodeWithSelector(IERC721.transferFrom.selector, from, to, tokenId))
    
    // Allow receiving ETH
    receive() external payable {}
}

/**
 * @title Complete EOA Inheritance Flow
 * @dev Demonstrates the complete flow from setup to EOA control
 */
contract EOAInheritanceFlow {
    
    InheritanceManager public inheritanceManager;
    EIP7702InheritanceController public controller;
    
    constructor() {
        inheritanceManager = new InheritanceManager();
        controller = new EIP7702InheritanceController(address(inheritanceManager));
    }
    
    /**
     * @notice Demonstrate the complete inheritance flow
     */
    function demonstrateFlow() external {
        address eoaAccount = address(0x123); // The EOA account
        address inheritor = address(0x456);  // The inheritor
        
        // Step 1: EOA owner configures inheritance
        // (This would be called by the EOA owner)
        // inheritanceManager.configureInheritance(eoaAccount, inheritor, 1_314_000);
        
        // Step 2: EOA continues normal operations
        // The EOA can use any existing EIP-7702 delegator for daily operations
        
        // Step 3: When inheritance is needed:
        // a. Someone marks inactivity start
        // b. Wait for inactivity period  
        // c. Inheritor claims inheritance
        // inheritanceManager.claimInheritance(eoaAccount, ...);
        
        // Step 4: EIP-7702 delegation setup
        // IMPORTANT: This requires the EOA's private key OR a pre-signed delegation
        //
        // Option A: EOA owner sets up delegation before becoming inactive
        // Option B: Inheritor uses pre-signed delegation authorization
        // Option C: Social recovery mechanism with delegation authority
        
        // Step 5: Inheritor now controls the EOA directly
        // controller.transferETH(inheritor, eoaAccount.balance);
        // controller.transferERC20(tokenAddress, inheritor, tokenBalance);
        // controller.execute(anyTarget, anyValue, anyData);
    }
}

/**
 * @title Production Implementation Guide
 */
contract ProductionGuide {
    
    /**
     * The complete production flow:
     * 
     * 1. Deploy InheritanceManager (once per network)
     * 2. Deploy EIP7702InheritanceController (once per network)
     * 
     * 3. For each EOA that wants inheritance:
     *    a. EOA owner calls: inheritanceManager.configureInheritance(eoaAddress, inheritor, period)
     *    b. EOA continues normal operations (can use any existing EIP-7702 delegator)
     * 
     * 4. When inheritance is claimed:
     *    a. inheritanceManager.claimInheritance(eoaAddress, ...)
     *    b. EOA sets up EIP-7702 delegation to EIP7702InheritanceController
     *    c. Inheritor can now control the EOA directly:
     *       - controller.transferETH(recipient, amount)
     *       - controller.transferERC20(token, recipient, amount)  
     *       - controller.execute(target, value, data)
     * 
     * Key Benefits:
     * ✅ Inheritor controls the actual EOA account
     * ✅ All assets (ETH, tokens, NFTs) are accessible
     * ✅ EOA can interact with any contract as if inheritor owns it
     * ✅ No asset transfer needed - inheritor IS the new EOA controller
     * ✅ Works with existing EIP-7702 infrastructure
     */
}

/**
 * @title JavaScript Integration Example
 */
contract JavaScriptExample {
    
    /**
     * // After inheritance is claimed, inheritor sets up EIP-7702 delegation:
     * 
     * const eoaAccount = "0x123..."; // The inherited EOA
     * const controllerAddress = "0x456..."; // EIP7702InheritanceController
     * const inheritorPrivateKey = "0x789..."; // Inheritor's private key
     * 
     * // Set up EIP-7702 delegation (this makes the EOA delegate to controller)
     * await setEIP7702Delegation(eoaAccount, controllerAddress);
     * 
     * // Now inheritor can control the EOA directly:
     * const controller = new ethers.Contract(controllerAddress, abi, inheritorSigner);
     * 
     * // Transfer ETH from the EOA
     * await controller.transferETH(inheritorAddress, ethers.parseEther("1.0"));
     * 
     * // Transfer tokens from the EOA  
     * await controller.transferERC20(tokenAddress, inheritorAddress, tokenAmount);
     * 
     * // Execute any transaction from the EOA
     * await controller.execute(targetContract, value, callData);
     * 
     * // The EOA account now behaves as if the inheritor owns it!
     */
}


