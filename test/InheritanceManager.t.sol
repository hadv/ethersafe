// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/InheritanceManager.sol";
import "./helpers/StateProofHelper.sol";

/**
 * @title InheritanceManagerTest
 * @dev Tests for the InheritanceManager that works with existing EIP-7702 delegators
 */
contract InheritanceManagerTest is Test {
    InheritanceManager public inheritanceManager;
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
        inheritanceManager = new InheritanceManager();
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

    function testBalanceChangesDoNotAffectInactivity() public {
        // Configure inheritance
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);

        // Mark inactivity start
        uint256 startNonce = vm.getNonce(accountOwner);
        uint256 startBalance = accountOwner.balance;

        // Use current block for testing (blockhash works for recent blocks)
        uint256 currentBlock = block.number;
        vm.roll(currentBlock + 1); // Move to next block so we can get hash of currentBlock

        // Generate test block header and account state proof
        bytes memory blockHeaderRLP = stateProofHelper.generateBlockHeaderRLP(currentBlock);

        InheritanceManager.AccountStateProof memory accountStateProof = InheritanceManager.AccountStateProof({
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
        vm.roll(currentBlock + INACTIVITY_PERIOD + 1);

        // Inheritance should still be claimable because nonce didn't change
        // (even though balance changed)
        uint256 newBalance = accountOwner.balance;
        assertEq(newBalance, startBalance + 5 ether); // Balance changed
        assertEq(vm.getNonce(accountOwner), startNonce); // Nonce unchanged

        // Claim inheritance should succeed
        uint256 claimBlockNumber = currentBlock + INACTIVITY_PERIOD + 1;
        bytes memory claimBlockHeaderRLP = stateProofHelper.generateBlockHeaderRLP(claimBlockNumber);

        InheritanceManager.AccountStateProof memory claimAccountStateProof = InheritanceManager.AccountStateProof({
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
        vm.roll(TEST_BLOCK + 100);

        bytes memory blockHeaderRLP = stateProofHelper.generateBlockHeaderRLP(TEST_BLOCK + 100);

        InheritanceManager.AccountStateProof memory accountStateProof = InheritanceManager.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, 42, 5 ether)
        });

        inheritanceManager.markInactivityStartWithProof(accountOwner, blockHeaderRLP, accountStateProof);
        
        // Step 3: Wait for inactivity period
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1);

        // Step 4: Claim inheritance
        vm.prank(inheritor);
        
        vm.expectEmit(true, true, false, false);
        emit InheritanceClaimed(accountOwner, inheritor);
        
        uint256 claimBlockNumber = TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1;
        bytes memory claimBlockHeaderRLP = stateProofHelper.generateBlockHeaderRLP(claimBlockNumber);

        InheritanceManager.AccountStateProof memory claimAccountStateProof = InheritanceManager.AccountStateProof({
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

    function testInheritanceClaimTooEarly() public {
        // Configure and mark inactivity
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);
        
        vm.roll(TEST_BLOCK + 100);

        bytes memory blockHeaderRLP = stateProofHelper.generateBlockHeaderRLP(TEST_BLOCK + 100);

        InheritanceManager.AccountStateProof memory accountStateProof = InheritanceManager.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, 42, 5 ether)
        });

        inheritanceManager.markInactivityStartWithProof(accountOwner, blockHeaderRLP, accountStateProof);
        
        // Try to claim before period ends
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD / 2);
        
        vm.prank(inheritor);
        vm.expectRevert(abi.encodeWithSelector(
            InheritanceManager.InactivityPeriodNotMet.selector
        ));
        
        uint256 earlyClaimBlockNumber = TEST_BLOCK + 100 + INACTIVITY_PERIOD / 2;
        bytes memory earlyClaimBlockHeaderRLP = stateProofHelper.generateBlockHeaderRLP(earlyClaimBlockNumber);

        InheritanceManager.AccountStateProof memory earlyClaimAccountStateProof = InheritanceManager.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, 42, 5 ether)
        });

        inheritanceManager.claimInheritanceWithProof(accountOwner, earlyClaimBlockHeaderRLP, earlyClaimAccountStateProof);
    }

    function testInheritanceClaimAccountActive() public {
        // Configure and mark inactivity
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);
        
        vm.roll(TEST_BLOCK + 100);

        bytes memory blockHeaderRLP = stateProofHelper.generateBlockHeaderRLP(TEST_BLOCK + 100);

        InheritanceManager.AccountStateProof memory accountStateProof = InheritanceManager.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, 42, 5 ether)
        });

        inheritanceManager.markInactivityStartWithProof(accountOwner, blockHeaderRLP, accountStateProof);
        
        // Wait for period to pass
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1);
        
        // Try to claim with different nonce (account became active)
        vm.prank(inheritor);
        vm.expectRevert(abi.encodeWithSelector(
            InheritanceManager.AccountStillActive.selector
        ));
        
        uint256 activeClaimBlockNumber = TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1;
        bytes memory activeClaimBlockHeaderRLP = stateProofHelper.generateBlockHeaderRLP(activeClaimBlockNumber);

        InheritanceManager.AccountStateProof memory activeClaimAccountStateProof = InheritanceManager.AccountStateProof({
            nonce: 43, // different nonce (account became active)
            balance: 5 ether,
            storageHash: keccak256(abi.encodePacked("storage", accountOwner)),
            codeHash: keccak256(abi.encodePacked("code", accountOwner)),
            proof: stateProofHelper.generateAccountProof(accountOwner, 43, 5 ether)
        });

        inheritanceManager.claimInheritanceWithProof(accountOwner, activeClaimBlockHeaderRLP, activeClaimAccountStateProof);
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

        bytes memory blockHeaderRLP = stateProofHelper.generateBlockHeaderRLP(TEST_BLOCK + 100);

        InheritanceManager.AccountStateProof memory accountStateProof = InheritanceManager.AccountStateProof({
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
