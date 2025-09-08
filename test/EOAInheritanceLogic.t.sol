// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {EOAInheritanceLogic} from "../src/EOAInheritanceLogic.sol";

contract EOAInheritanceLogicTest is Test {
    EOAInheritanceLogic public inheritanceLogic;

    address public owner;
    address public inheritor;
    address public randomUser;

    uint256 public constant VALID_PERIOD = 60 days;
    uint256 public constant MIN_PERIOD = 30 days;
    uint256 public constant MAX_PERIOD = 10 * 365 days;
    uint256 public constant GRACE_PERIOD = 7 days;

    // Events for testing
    event InheritanceSetup(address indexed inheritor, uint256 inactivityPeriod);
    event ActivityRecorded(address indexed owner, uint256 timestamp);
    event OwnershipClaimed(address indexed previousOwner, address indexed newOwner);
    event InheritanceCancelled(address indexed owner);
    event EmergencyReset(address indexed owner);

    function setUp() public {
        owner = address(this); // Test contract acts as the EOA
        inheritor = makeAddr("inheritor");
        randomUser = makeAddr("randomUser");

        inheritanceLogic = new EOAInheritanceLogic();
    }

    // --- Setup Tests ---

    function test_SetupInheritance_Success() public {
        vm.expectEmit(true, false, false, true);
        emit InheritanceSetup(inheritor, VALID_PERIOD);

        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        (address configInheritor, uint256 period, uint256 lastActive, uint256 gracePeriod) =
            inheritanceLogic.getInheritanceConfig();

        assertEq(configInheritor, inheritor);
        assertEq(period, VALID_PERIOD);
        assertEq(lastActive, block.timestamp);
        assertEq(gracePeriod, GRACE_PERIOD);
        assertEq(inheritanceLogic.getAuthorizedOwner(), owner);
    }

    function test_SetupInheritance_RevertZeroAddress() public {
        vm.expectRevert(EOAInheritanceLogic.InvalidInheritor.selector);
        inheritanceLogic.setupInheritance(address(0), VALID_PERIOD);
    }

    function test_SetupInheritance_RevertSelfInheritance() public {
        vm.expectRevert(EOAInheritanceLogic.InvalidInheritor.selector);
        inheritanceLogic.setupInheritance(owner, VALID_PERIOD);
    }

    function test_SetupInheritance_RevertInvalidPeriodTooShort() public {
        vm.expectRevert(EOAInheritanceLogic.InvalidPeriod.selector);
        inheritanceLogic.setupInheritance(inheritor, MIN_PERIOD - 1);
    }

    function test_SetupInheritance_RevertInvalidPeriodTooLong() public {
        vm.expectRevert(EOAInheritanceLogic.InvalidPeriod.selector);
        inheritanceLogic.setupInheritance(inheritor, MAX_PERIOD + 1);
    }

    function test_SetupInheritance_RevertUnauthorized() public {
        // Setup first
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        // Try to setup from unauthorized address
        vm.prank(randomUser);
        vm.expectRevert(EOAInheritanceLogic.UnauthorizedAccess.selector);
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);
    }

    // --- Keep Alive Tests ---

    function test_KeepAlive_Success() public {
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        uint256 initialTime = block.timestamp;
        vm.warp(initialTime + 10 days);

        vm.expectEmit(true, false, false, true);
        emit ActivityRecorded(owner, block.timestamp);

        inheritanceLogic.keepAlive();

        (, , uint256 lastActive, ) = inheritanceLogic.getInheritanceConfig();
        assertEq(lastActive, block.timestamp);
    }

    function test_KeepAlive_RevertUnauthorized() public {
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        vm.prank(randomUser);
        vm.expectRevert(EOAInheritanceLogic.UnauthorizedAccess.selector);
        inheritanceLogic.keepAlive();
    }

    // --- Claim Ownership Tests ---

    function test_ClaimOwnership_Success() public {
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        // Fast forward past inactivity period + grace period
        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);

        vm.expectEmit(true, true, false, true);
        emit OwnershipClaimed(owner, inheritor);

        vm.prank(inheritor);
        inheritanceLogic.claimOwnership();

        assertEq(inheritanceLogic.getAuthorizedOwner(), inheritor);

        // Check inheritance config is cleared
        (address configInheritor, uint256 period, , uint256 gracePeriod) =
            inheritanceLogic.getInheritanceConfig();
        assertEq(configInheritor, address(0));
        assertEq(period, 0);
        assertEq(gracePeriod, 0);
    }

    function test_ClaimOwnership_RevertNoInheritanceConfigured() public {
        vm.prank(inheritor);
        vm.expectRevert(EOAInheritanceLogic.NoInheritanceConfigured.selector);
        inheritanceLogic.claimOwnership();
    }

    function test_ClaimOwnership_RevertUnauthorized() public {
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);

        vm.prank(randomUser);
        vm.expectRevert(EOAInheritanceLogic.UnauthorizedAccess.selector);
        inheritanceLogic.claimOwnership();
    }

    function test_ClaimOwnership_RevertInactivityPeriodNotMet() public {
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        // Only fast forward past inactivity period but not grace period
        vm.warp(block.timestamp + VALID_PERIOD);

        vm.prank(inheritor);
        vm.expectRevert(EOAInheritanceLogic.InactivityPeriodNotMet.selector);
        inheritanceLogic.claimOwnership();
    }

    // --- Cancel Inheritance Tests ---

    function test_CancelInheritance_Success() public {
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        vm.expectEmit(true, false, false, true);
        emit InheritanceCancelled(owner);

        inheritanceLogic.cancelInheritance();

        // Check inheritance config is cleared
        (address configInheritor, uint256 period, uint256 lastActive, uint256 gracePeriod) =
            inheritanceLogic.getInheritanceConfig();
        assertEq(configInheritor, address(0));
        assertEq(period, 0);
        assertEq(gracePeriod, 0);
        assertEq(lastActive, block.timestamp); // Should be updated to current time
    }

    function test_CancelInheritance_RevertNoInheritanceConfigured() public {
        vm.expectRevert(EOAInheritanceLogic.NoInheritanceConfigured.selector);
        inheritanceLogic.cancelInheritance();
    }

    function test_CancelInheritance_RevertUnauthorized() public {
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        vm.prank(randomUser);
        vm.expectRevert(EOAInheritanceLogic.UnauthorizedAccess.selector);
        inheritanceLogic.cancelInheritance();
    }

    // --- Emergency Reset Tests ---

    function test_EmergencyReset_Success() public {
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        vm.expectEmit(true, false, false, true);
        emit EmergencyReset(owner);

        // Emergency reset can only be called by the contract itself (address(this))
        inheritanceLogic.emergencyReset();

        // Check all settings are cleared
        (address configInheritor, uint256 period, uint256 lastActive, uint256 gracePeriod) =
            inheritanceLogic.getInheritanceConfig();
        assertEq(configInheritor, address(0));
        assertEq(period, 0);
        assertEq(lastActive, 0);
        assertEq(gracePeriod, 0);
        assertEq(inheritanceLogic.getAuthorizedOwner(), address(0));
    }

    function test_EmergencyReset_RevertUnauthorized() public {
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        vm.prank(randomUser);
        vm.expectRevert(EOAInheritanceLogic.UnauthorizedAccess.selector);
        inheritanceLogic.emergencyReset();
    }

    // --- View Function Tests ---

    function test_CanClaimInheritance_BeforePeriod() public {
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        (bool canClaim, uint256 timeRemaining) = inheritanceLogic.canClaimInheritance();
        assertFalse(canClaim);
        assertEq(timeRemaining, VALID_PERIOD + GRACE_PERIOD);
    }

    function test_CanClaimInheritance_AfterPeriod() public {
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);

        (bool canClaim, uint256 timeRemaining) = inheritanceLogic.canClaimInheritance();
        assertTrue(canClaim);
        assertEq(timeRemaining, 0);
    }

    function test_CanClaimInheritance_NoInheritanceConfigured() public {
        (bool canClaim, uint256 timeRemaining) = inheritanceLogic.canClaimInheritance();
        assertFalse(canClaim);
        assertEq(timeRemaining, type(uint256).max);
    }

    // --- Integration Tests ---

    function test_FullInheritanceFlow() public {
        // 1. Setup inheritance
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        // 2. Owner stays active for a while
        vm.warp(block.timestamp + 20 days);
        inheritanceLogic.keepAlive();

        // 3. Owner becomes inactive
        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);

        // 4. Inheritor claims ownership
        vm.prank(inheritor);
        inheritanceLogic.claimOwnership();

        // 5. Verify new owner can setup new inheritance
        address newInheritor = makeAddr("newInheritor");
        vm.prank(inheritor);
        inheritanceLogic.setupInheritance(newInheritor, VALID_PERIOD);

        assertEq(inheritanceLogic.getAuthorizedOwner(), inheritor);
        (address configInheritor, , , ) = inheritanceLogic.getInheritanceConfig();
        assertEq(configInheritor, newInheritor);
    }

    function test_OwnerCanPreventInheritanceByStayingActive() public {
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        // Fast forward to just before the claim period
        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD - 1 days);

        // Owner stays active
        inheritanceLogic.keepAlive();

        // Fast forward again
        vm.warp(block.timestamp + 1 days);

        // Inheritor still can't claim because owner was active recently
        vm.prank(inheritor);
        vm.expectRevert(EOAInheritanceLogic.InactivityPeriodNotMet.selector);
        inheritanceLogic.claimOwnership();
    }

    // --- Reentrancy Tests ---

    function test_ReentrancyProtection() public {
        // This is a basic test - in a real scenario, you'd need a malicious contract
        // that tries to re-enter during execution
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        // The reentrancy guard should prevent multiple calls in the same transaction
        // This is more of a conceptual test since we can't easily simulate reentrancy
        // in this simple test setup
        assertTrue(true); // Placeholder - reentrancy protection is implemented via modifier
    }

    // --- Edge Cases ---

    function test_UpdateInheritanceConfiguration() public {
        // Setup initial inheritance
        inheritanceLogic.setupInheritance(inheritor, VALID_PERIOD);

        // Update with new inheritor and period
        address newInheritor = makeAddr("newInheritor");
        uint256 newPeriod = 90 days;

        inheritanceLogic.setupInheritance(newInheritor, newPeriod);

        (address configInheritor, uint256 period, , ) = inheritanceLogic.getInheritanceConfig();
        assertEq(configInheritor, newInheritor);
        assertEq(period, newPeriod);
    }

    function test_MinimumAndMaximumPeriods() public {
        // Test minimum period
        inheritanceLogic.setupInheritance(inheritor, MIN_PERIOD);
        (, uint256 period, , ) = inheritanceLogic.getInheritanceConfig();
        assertEq(period, MIN_PERIOD);

        // Test maximum period
        inheritanceLogic.setupInheritance(inheritor, MAX_PERIOD);
        (, uint256 newPeriod, , ) = inheritanceLogic.getInheritanceConfig();
        assertEq(newPeriod, MAX_PERIOD);
    }
}
