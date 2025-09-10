// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/InheritanceManager.sol";

/**
 * @title InheritanceManagerTest
 * @dev Tests for the InheritanceManager that works with existing EIP-7702 delegators
 */
contract InheritanceManagerTest is Test {
    InheritanceManager public inheritanceManager;
    
    // Mock EIP-7702 delegator
    MockEIP7702Delegator public delegator;
    MockERC20 public mockToken;
    
    // Test accounts
    address public accountOwner = address(0x1);
    address public inheritor = address(0x2);
    address public unauthorized = address(0x3);
    
    // Test parameters
    uint256 public constant INACTIVITY_PERIOD = 1_314_000; // ~6 months
    uint256 public constant TEST_BLOCK = 1000;
    
    event InheritanceConfigured(address indexed account, address indexed inheritor, uint256 inactivityPeriod);
    event InheritanceClaimed(address indexed account, address indexed inheritor);

    function setUp() public {
        // Deploy contracts
        inheritanceManager = new InheritanceManager();
        delegator = new MockEIP7702Delegator();
        mockToken = new MockERC20("Test Token", "TEST");
        
        // Fund test accounts
        vm.deal(accountOwner, 10 ether);
        vm.deal(inheritor, 1 ether);
        vm.deal(unauthorized, 1 ether);
        
        // Set current block number
        vm.roll(TEST_BLOCK);
    }

    // --- Inheritance Configuration Tests ---

    function testConfigureInheritance() public {
        vm.prank(accountOwner);
        
        vm.expectEmit(true, true, false, true);
        emit InheritanceConfigured(accountOwner, inheritor, INACTIVITY_PERIOD);
        
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);
        
        (address configuredInheritor, uint256 period, bool isActive) = 
            inheritanceManager.getInheritanceConfig(accountOwner);
        
        assertEq(configuredInheritor, inheritor);
        assertEq(period, INACTIVITY_PERIOD);
        assertTrue(isActive);
    }

    function testConfigureInheritanceUnauthorized() public {
        vm.prank(unauthorized);
        
        vm.expectRevert(abi.encodeWithSelector(
            InheritanceManager.UnauthorizedCaller.selector
        ));
        
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);
    }

    function testConfigureInheritanceWithAuthorizedSigner() public {
        // Account owner authorizes a signer
        vm.prank(accountOwner);
        inheritanceManager.authorizeSigner(unauthorized);
        
        // Authorized signer can configure inheritance
        vm.prank(unauthorized);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);
        
        (address configuredInheritor, uint256 period, bool isActive) = 
            inheritanceManager.getInheritanceConfig(accountOwner);
        
        assertEq(configuredInheritor, inheritor);
        assertEq(period, INACTIVITY_PERIOD);
        assertTrue(isActive);
    }

    function testRevokeInheritance() public {
        // Configure inheritance first
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);
        
        // Revoke inheritance
        vm.prank(accountOwner);
        inheritanceManager.revokeInheritance(accountOwner);
        
        // Verify revocation
        (address configuredInheritor, uint256 period, bool isActive) = 
            inheritanceManager.getInheritanceConfig(accountOwner);
        
        assertEq(configuredInheritor, address(0));
        assertEq(period, 0);
        assertFalse(isActive);
    }

    // No testRegisterAssets needed!
    // With EIP-7702 delegation, inheritor automatically gets access to ALL assets

    // --- Complete Inheritance Flow Tests ---

    function testCompleteInheritanceFlow() public {
        // Step 1: Configure inheritance
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);
        
        // Step 2: Mark inactivity start (no asset registration needed!)
        vm.roll(TEST_BLOCK + 100);
        bytes memory stateProof = abi.encode("mock_proof");
        
        inheritanceManager.markInactivityStart(
            accountOwner,
            TEST_BLOCK + 100,
            42, // nonce
            5 ether, // balance
            stateProof
        );
        
        // Step 3: Wait for inactivity period
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1);

        // Step 4: Claim inheritance
        vm.prank(inheritor);
        
        vm.expectEmit(true, true, false, false);
        emit InheritanceClaimed(accountOwner, inheritor);
        
        inheritanceManager.claimInheritance(
            accountOwner,
            TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1,
            42, // same nonce (inactive)
            5 ether, // same balance (inactive)
            stateProof
        );
        
        // Verify inheritance claimed
        assertTrue(inheritanceManager.isInheritanceClaimed(accountOwner));
        assertEq(inheritanceManager.authorizedSigners(accountOwner), inheritor);
    }

    function testInheritanceClaimTooEarly() public {
        // Configure and mark inactivity
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);
        
        vm.roll(TEST_BLOCK + 100);
        bytes memory stateProof = abi.encode("mock_proof");
        
        inheritanceManager.markInactivityStart(accountOwner, TEST_BLOCK + 100, 42, 5 ether, stateProof);
        
        // Try to claim before period ends
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD / 2);
        
        vm.prank(inheritor);
        vm.expectRevert(abi.encodeWithSelector(
            InheritanceManager.InactivityPeriodNotMet.selector
        ));
        
        inheritanceManager.claimInheritance(accountOwner, TEST_BLOCK + 100 + INACTIVITY_PERIOD / 2, 42, 5 ether, stateProof);
    }

    function testInheritanceClaimAccountActive() public {
        // Configure and mark inactivity
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);
        
        vm.roll(TEST_BLOCK + 100);
        bytes memory stateProof = abi.encode("mock_proof");
        
        inheritanceManager.markInactivityStart(accountOwner, TEST_BLOCK + 100, 42, 5 ether, stateProof);
        
        // Wait for period to pass
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1);
        
        // Try to claim with different nonce (account became active)
        vm.prank(inheritor);
        vm.expectRevert(abi.encodeWithSelector(
            InheritanceManager.AccountStillActive.selector
        ));
        
        inheritanceManager.claimInheritance(
            accountOwner,
            TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1,
            43, // different nonce
            5 ether,
            stateProof
        );
    }

    // --- View Function Tests ---

    function testCanClaimInheritance() public {
        // Configure inheritance
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);
        
        // Before marking inactivity
        (bool canClaim, uint256 blocksRemaining,,) = inheritanceManager.canClaimInheritance(accountOwner);
        assertFalse(canClaim);
        assertEq(blocksRemaining, 0);
        
        // Mark inactivity
        vm.roll(TEST_BLOCK + 100);
        bytes memory stateProof = abi.encode("mock_proof");
        inheritanceManager.markInactivityStart(accountOwner, TEST_BLOCK + 100, 42, 5 ether, stateProof);
        
        // Before period completion
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD / 2);
        (canClaim, blocksRemaining,,) = inheritanceManager.canClaimInheritance(accountOwner);
        assertFalse(canClaim);
        assertGt(blocksRemaining, 0);
        
        // After period completion
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1);
        (canClaim, blocksRemaining,,) = inheritanceManager.canClaimInheritance(accountOwner);
        assertTrue(canClaim);
        assertEq(blocksRemaining, 0);
    }
}

// --- Mock Contracts ---

contract MockEIP7702Delegator {
    function execute(address to, uint256 value, bytes calldata data) external payable returns (bytes memory) {
        (bool success, bytes memory result) = to.call{value: value}(data);
        require(success, "Execution failed");
        return result;
    }
}

contract MockERC20 {
    string public name;
    string public symbol;
    mapping(address => uint256) public balanceOf;
    
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}
