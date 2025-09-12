// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/InheritanceManager.sol";
import "../src/libraries/EthereumStateVerification.sol";
import "./helpers/InheritanceManagerTestHelper.sol";
import "./helpers/StateProofHelper.sol";

/**
 * @title InheritanceManagerTest
 * @dev Tests for the InheritanceManager that works with existing EIP-7702 delegators
 */
contract InheritanceManagerTest is Test {
    InheritanceManagerTestHelper public inheritanceManager;
    StateProofHelper public stateProofHelper;

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
        inheritanceManager = new InheritanceManagerTestHelper();
        stateProofHelper = new StateProofHelper();
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

        vm.expectRevert(abi.encodeWithSelector(InheritanceManager.UnauthorizedCaller.selector));

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

    function testBalanceChangesDoNotAffectInactivity() public {
        // Configure inheritance
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);

        // Mark inactivity start
        uint256 startNonce = vm.getNonce(accountOwner);
        uint256 startBalance = accountOwner.balance;

        // Use test helper to create simple test data
        uint256 targetBlock = block.number;
        bytes32 testStateRoot = inheritanceManager.createTestStateRoot(targetBlock);
        bytes memory blockHeaderRLP = inheritanceManager.createTestBlockHeader(targetBlock, testStateRoot);

        StateVerifier.AccountStateProof memory accountStateProof = StateVerifier.AccountStateProof({
            nonce: startNonce,
            balance: startBalance,
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, startNonce, startBalance)
        });

        vm.prank(accountOwner);
        inheritanceManager.markInactivityStartWithProof(accountOwner, blockHeaderRLP, accountStateProof);

        // Simulate receiving ETH (balance increases without nonce change)
        vm.deal(accountOwner, startBalance + 5 ether);

        // Move forward in time past the inactivity period
        vm.roll(targetBlock + INACTIVITY_PERIOD + 1);

        // Inheritance should still be claimable because nonce didn't change
        // (even though balance changed)
        uint256 newBalance = accountOwner.balance;
        assertEq(newBalance, startBalance + 5 ether); // Balance changed
        assertEq(vm.getNonce(accountOwner), startNonce); // Nonce unchanged

        // Claim inheritance should succeed
        uint256 claimBlockNumber = targetBlock + INACTIVITY_PERIOD + 1;
        bytes32 claimStateRoot = inheritanceManager.createTestStateRoot(claimBlockNumber);
        bytes memory claimBlockHeaderRLP = inheritanceManager.createTestBlockHeader(claimBlockNumber, claimStateRoot);

        StateVerifier.AccountStateProof memory claimAccountStateProof = StateVerifier.AccountStateProof({
            nonce: startNonce, // Same nonce (inactive)
            balance: newBalance, // Updated balance
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, startNonce, newBalance)
        });

        vm.prank(inheritor);
        inheritanceManager.claimInheritanceWithProof(accountOwner, claimBlockHeaderRLP, claimAccountStateProof);

        // Verify inheritance was claimed
        assertTrue(inheritanceManager.isInheritanceClaimed(accountOwner));
    }

    // No testRegisterAssets needed!
    // With EIP-7702 delegation, inheritor automatically gets access to ALL assets

    // --- Complete Inheritance Flow Tests ---

    function testCompleteInheritanceFlow() public {
        // Step 1: Configure inheritance
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);

        // Step 2: Mark inactivity start (no asset registration needed!)
        uint256 inactivityBlock = block.number;

        // Use test helper to create test data
        bytes32 testStateRoot = inheritanceManager.createTestStateRoot(inactivityBlock);
        bytes memory blockHeaderRLP = inheritanceManager.createTestBlockHeader(inactivityBlock, testStateRoot);

        StateVerifier.AccountStateProof memory accountStateProof = StateVerifier.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, 42, 5 ether)
        });

        inheritanceManager.markInactivityStartWithProof(accountOwner, blockHeaderRLP, accountStateProof);

        // Step 3: Wait for inactivity period
        vm.roll(inactivityBlock + INACTIVITY_PERIOD + 1);

        // Step 4: Claim inheritance
        vm.prank(inheritor);

        vm.expectEmit(true, true, false, false);
        emit InheritanceClaimed(accountOwner, inheritor);

        uint256 claimBlockNumber = inactivityBlock + INACTIVITY_PERIOD + 1;
        bytes32 claimStateRoot = inheritanceManager.createTestStateRoot(claimBlockNumber);
        bytes memory claimBlockHeaderRLP = inheritanceManager.createTestBlockHeader(claimBlockNumber, claimStateRoot);

        StateVerifier.AccountStateProof memory claimAccountStateProof = StateVerifier.AccountStateProof({
            nonce: 42, // same nonce (inactive)
            balance: 5 ether, // same balance (inactive)
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, 42, 5 ether)
        });

        inheritanceManager.claimInheritanceWithProof(accountOwner, claimBlockHeaderRLP, claimAccountStateProof);

        // Verify inheritance claimed
        assertTrue(inheritanceManager.isInheritanceClaimed(accountOwner));
        assertEq(inheritanceManager.authorizedSigners(accountOwner), inheritor);
    }

    function testClaimInheritanceDirectDebug() public {
        // Configure inheritance
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);

        // Mark inactivity directly
        inheritanceManager.markInactivityStartDirect(accountOwner, 1000, 42, 5 ether);

        // Move forward in time
        vm.roll(1000 + INACTIVITY_PERIOD + 1);

        // Try to claim directly
        vm.prank(inheritor);
        inheritanceManager.claimInheritanceDirect(accountOwner, 1000 + INACTIVITY_PERIOD + 1, 42);

        // Verify inheritance claimed
        assertTrue(inheritanceManager.isInheritanceClaimed(accountOwner));
    }

    function testCallerDebug() public {
        // Test who the caller is when using vm.prank
        vm.prank(inheritor);
        address caller = inheritanceManager.whoIsCaller();
        assertEq(caller, inheritor, "Caller should be inheritor");

        // Test what caller is received in claimInheritanceWithProof
        vm.prank(inheritor);
        bytes memory dummyHeader = hex"00";
        StateVerifier.AccountStateProof memory dummyProof = StateVerifier.AccountStateProof({
            nonce: 0,
            balance: 0,
            storageHash: bytes32(0),
            codeHash: bytes32(0),
            proof: new bytes32[](0)
        });
        address claimCaller = inheritanceManager.debugClaimInheritanceWithProof(accountOwner, dummyHeader, dummyProof);
        assertEq(claimCaller, inheritor, "Claim caller should be inheritor");

        // Test authorization check
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);

        (address configuredInheritor, bool isAuthorized) =
            inheritanceManager.debugClaimAuthorization(accountOwner, inheritor);
        assertEq(configuredInheritor, inheritor, "Configured inheritor should match");
        assertTrue(isAuthorized, "Inheritor should be authorized");

        // Test the exact same logic as used in _claimInheritanceInternal
        bool internalAuth = inheritanceManager.debugAuthorizationInternal(accountOwner, inheritor);
        assertTrue(internalAuth, "Internal authorization should pass");
    }

    function testMinimalClaimReproduction() public {
        // Minimal reproduction of the claim issue
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);

        // Mark inactivity
        inheritanceManager.markInactivityStartDirect(accountOwner, 1000, 42, 5 ether);

        // Move forward in time
        vm.roll(1000 + INACTIVITY_PERIOD + 1);

        // Check authorization before claim
        (address configuredInheritor, bool isAuthorized) =
            inheritanceManager.debugClaimAuthorization(accountOwner, inheritor);
        assertEq(configuredInheritor, inheritor, "Configured inheritor should match");
        assertTrue(isAuthorized, "Inheritor should be authorized");

        // Try to claim with the exact same addresses
        vm.prank(inheritor);
        inheritanceManager.claimInheritanceDirect(accountOwner, 1000 + INACTIVITY_PERIOD + 1, 42);

        assertTrue(inheritanceManager.isInheritanceClaimed(accountOwner));
    }

    function testInheritanceClaimTooEarly() public {
        // Configure and mark inactivity
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);

        vm.roll(TEST_BLOCK + 100);

        bytes32 testStateRoot = inheritanceManager.createTestStateRoot(TEST_BLOCK + 100);
        bytes memory blockHeaderRLP = inheritanceManager.createTestBlockHeader(TEST_BLOCK + 100, testStateRoot);

        StateVerifier.AccountStateProof memory accountStateProof = StateVerifier.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, 42, 5 ether)
        });

        inheritanceManager.markInactivityStartWithProof(accountOwner, blockHeaderRLP, accountStateProof);

        // Try to claim before period ends
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD / 2);

        uint256 earlyClaimBlockNumber = TEST_BLOCK + 100 + INACTIVITY_PERIOD / 2;
        bytes32 earlyClaimStateRoot = inheritanceManager.createTestStateRoot(earlyClaimBlockNumber);
        bytes memory earlyClaimBlockHeaderRLP =
            inheritanceManager.createTestBlockHeader(earlyClaimBlockNumber, earlyClaimStateRoot);

        StateVerifier.AccountStateProof memory earlyClaimAccountStateProof = StateVerifier.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, 42, 5 ether)
        });

        vm.prank(inheritor);
        vm.expectRevert(abi.encodeWithSelector(InheritanceManager.InactivityPeriodNotMet.selector));
        inheritanceManager.claimInheritanceWithProof(
            accountOwner, earlyClaimBlockHeaderRLP, earlyClaimAccountStateProof
        );
    }

    function testInheritanceClaimAccountActive() public {
        // Configure and mark inactivity
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);

        vm.roll(TEST_BLOCK + 100);

        bytes32 testStateRoot = inheritanceManager.createTestStateRoot(TEST_BLOCK + 100);
        bytes memory blockHeaderRLP = inheritanceManager.createTestBlockHeader(TEST_BLOCK + 100, testStateRoot);

        StateVerifier.AccountStateProof memory accountStateProof = StateVerifier.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, 42, 5 ether)
        });

        inheritanceManager.markInactivityStartWithProof(accountOwner, blockHeaderRLP, accountStateProof);

        // Wait for period to pass
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1);

        uint256 activeClaimBlockNumber = TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1;
        bytes32 activeClaimStateRoot = inheritanceManager.createTestStateRoot(activeClaimBlockNumber);
        bytes memory activeClaimBlockHeaderRLP =
            inheritanceManager.createTestBlockHeader(activeClaimBlockNumber, activeClaimStateRoot);

        StateVerifier.AccountStateProof memory activeClaimAccountStateProof = StateVerifier.AccountStateProof({
            nonce: 43, // different nonce (account became active)
            balance: 5 ether,
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, 43, 5 ether)
        });

        // Try to claim with different nonce (account became active)
        vm.prank(inheritor);
        vm.expectRevert(abi.encodeWithSelector(InheritanceManager.AccountStillActive.selector));
        inheritanceManager.claimInheritanceWithProof(
            accountOwner, activeClaimBlockHeaderRLP, activeClaimAccountStateProof
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

        bytes32 testStateRoot = inheritanceManager.createTestStateRoot(TEST_BLOCK + 100);
        bytes memory blockHeaderRLP = inheritanceManager.createTestBlockHeader(TEST_BLOCK + 100, testStateRoot);

        StateVerifier.AccountStateProof memory accountStateProof = StateVerifier.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, 42, 5 ether)
        });

        inheritanceManager.markInactivityStartWithProof(accountOwner, blockHeaderRLP, accountStateProof);

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
