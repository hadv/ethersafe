// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../lib/account-abstraction/contracts/core/BareAccount.sol";
import "./InheritanceManager.sol";

/**
 * @title EIP7702InheritanceController
 * @dev Enhanced EIP-7702 controller using BareAccount library for inherited EOAs
 *
 * This contract becomes the delegation target for inherited EOAs via EIP-7702.
 * After inheritance is claimed, the inheritor can control the EOA directly.
 *
 * Key features:
 * - Inherits from BareAccount for optimized execution logic
 * - Better gas efficiency through assembly-optimized calls
 * - Simplified single execution interface
 * - Proper return data handling
 */
contract EIP7702InheritanceController is BareAccount {
    InheritanceManager public immutable inheritanceManager;

    constructor(address _inheritanceManager) {
        inheritanceManager = InheritanceManager(_inheritanceManager);
    }

    /**
     * @dev Override authorization logic to check inheritance status
     * This replaces the default "msg.sender == address(this)" check with inheritance verification
     */
    function _requireForExecute() internal view override {
        // Verify that inheritance has been claimed for this EOA
        require(inheritanceManager.isInheritanceClaimed(address(this)), "Inheritance not claimed");

        // Verify that the caller is the inheritor
        (address inheritor,,) = inheritanceManager.getInheritanceConfig(address(this));
        require(msg.sender == inheritor, "Not the inheritor");
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

    /**
     * @notice Get the current inheritor of this EOA
     */
    function getInheritor() external view returns (address) {
        (address inheritor,,) = inheritanceManager.getInheritanceConfig(address(this));
        return inheritor;
    }

    /**
     * @notice Check if inheritance has been claimed for this EOA
     */
    function isInheritanceClaimed() external view returns (bool) {
        return inheritanceManager.isInheritanceClaimed(address(this));
    }

    // Allow receiving ETH
    receive() external payable {}
}
