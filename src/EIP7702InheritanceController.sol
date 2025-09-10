// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./InheritanceManager.sol";

/**
 * @title EIP7702InheritanceController
 * @dev Simple and clean EIP-7702 controller for inherited EOAs
 * 
 * This contract becomes the delegation target for inherited EOAs via EIP-7702.
 * After inheritance is claimed, the inheritor can control the EOA directly.
 */
contract EIP7702InheritanceController {
    
    InheritanceManager public immutable inheritanceManager;
    
    constructor(address _inheritanceManager) {
        inheritanceManager = InheritanceManager(_inheritanceManager);
    }
    
    /**
     * @notice Execute any transaction from the inherited EOA
     * @dev This is the only function needed - it can handle all transfers and interactions
     * @param to Target address
     * @param value ETH value to send
     * @param data Call data
     * 
     * Examples:
     * - Transfer ETH: execute(recipient, amount, "")
     * - Transfer ERC20: execute(token, 0, abi.encodeWithSelector(IERC20.transfer.selector, recipient, amount))
     * - Transfer ERC721: execute(nft, 0, abi.encodeWithSelector(IERC721.transferFrom.selector, from, to, tokenId))
     * - Call any contract: execute(contract, value, callData)
     */
    function execute(address to, uint256 value, bytes calldata data) external payable returns (bytes memory) {
        // Verify that inheritance has been claimed for this EOA
        require(inheritanceManager.isInheritanceClaimed(address(this)), "Inheritance not claimed");
        
        // Verify that the caller is the inheritor
        (address inheritor,,) = inheritanceManager.getInheritanceConfig(address(this));
        require(msg.sender == inheritor, "Not the inheritor");
        
        // Execute the transaction from the EOA (address(this) is the EOA when delegated via EIP-7702)
        (bool success, bytes memory result) = to.call{value: value}(data);
        require(success, "Execution failed");
        
        return result;
    }
    
    /**
     * @notice Execute multiple transactions from the inherited EOA
     * @dev Convenience function for batch operations
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
    
    /**
     * @notice Check if this EOA can be controlled by the caller
     */
    function canControl(address caller) external view returns (bool) {
        if (!inheritanceManager.isInheritanceClaimed(address(this))) {
            return false;
        }
        
        (address inheritor,,) = inheritanceManager.getInheritanceConfig(address(this));
        return caller == inheritor;
    }
    
    // Allow receiving ETH
    receive() external payable {}
}