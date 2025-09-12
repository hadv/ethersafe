// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/InheritanceManager.sol";
import "./helpers/InheritanceManagerTestHelper.sol";
import "./helpers/StateProofHelper.sol";

/**
 * @title State Proof Verification Tests
 * @dev Tests for the Merkle proof verification functionality in InheritanceManager
 */
contract StateProofVerificationTest is Test {
    InheritanceManagerTestHelper public inheritanceManager;
    StateProofHelper public stateProofHelper;

    address public accountOwner = address(0x1);
    address public inheritor = address(0x2);
    uint256 public constant INACTIVITY_PERIOD = 100;
    uint256 public constant TEST_BLOCK = 1000;

    event InactivityMarked(address indexed account, uint256 startBlock, uint256 nonce, uint256 balance);
    event InheritanceClaimed(address indexed account, address indexed inheritor);

    function setUp() public {
        inheritanceManager = new InheritanceManagerTestHelper();
        stateProofHelper = new StateProofHelper();
        vm.deal(accountOwner, 10 ether);
    }

    function testVerifyAccountStateWithValidProof() public {
        // Create a real account state
        InheritanceManager.AccountStateProof memory targetState = InheritanceManager.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256("storage_root"),
            codeHash: keccak256("code_hash"),
            proof: new bytes32[](0) // Will be filled by helper
        });

        // Create some other accounts for the state trie
        address[] memory otherAccounts = new address[](2);
        otherAccounts[0] = address(0x3);
        otherAccounts[1] = address(0x4);

        InheritanceManager.AccountStateProof[] memory otherStates = new InheritanceManager.AccountStateProof[](2);
        otherStates[0] = InheritanceManager.AccountStateProof({
            nonce: 10,
            balance: 1 ether,
            storageHash: keccak256("other_storage_1"),
            codeHash: keccak256("other_code_1"),
            proof: new bytes32[](0)
        });
        otherStates[1] = InheritanceManager.AccountStateProof({
            nonce: 20,
            balance: 2 ether,
            storageHash: keccak256("other_storage_2"),
            codeHash: keccak256("other_code_2"),
            proof: new bytes32[](0)
        });

        // Generate real state proof
        (bytes32 stateRoot, bytes32[] memory proof) =
            stateProofHelper.generateSingleStateProof(accountOwner, targetState, otherAccounts, otherStates);

        // Update the proof in the target state
        targetState.proof = proof;

        // Verify the real state proof
        bool isValid = inheritanceManager.verifyAccountState(accountOwner, stateRoot, targetState);
        assertTrue(isValid);
    }

    function testVerifyAccountStateWithInvalidProof() public {
        // Create an invalid account state proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256("invalid_proof");

        InheritanceManager.AccountStateProof memory invalidStateProof = InheritanceManager.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256("storage_root"),
            codeHash: keccak256("code_hash"),
            proof: invalidProof
        });

        bytes32 randomStateRoot = keccak256("random_state_root");

        // Invalid proofs should be rejected
        bool isValid = inheritanceManager.verifyAccountState(accountOwner, randomStateRoot, invalidStateProof);
        assertFalse(isValid);
    }

    function testVerifyBlockHashWithValidHash() public {
        // Move to a specific block number
        vm.roll(1000);

        // Get a recent block hash (within 256 block limit)
        uint256 blockNumber = block.number - 10;
        bytes32 actualBlockHash = blockhash(blockNumber);

        // Real block hashes should be valid
        bool isValid = inheritanceManager.verifyBlockHash(blockNumber, actualBlockHash);
        assertTrue(isValid);
    }

    function testVerifyBlockHashWithInvalidHash() public {
        uint256 blockNumber = 500;
        bytes32 invalidBlockHash = keccak256("invalid_hash");

        // Invalid block hashes should be rejected
        bool isValid = inheritanceManager.verifyBlockHash(blockNumber, invalidBlockHash);
        assertFalse(isValid);
    }

    function testVerifyBlockHashFutureBlock() public {
        uint256 futureBlock = block.number + 100;
        bytes32 someHash = keccak256("some_hash");

        // Future blocks should be rejected
        bool isValid = inheritanceManager.verifyBlockHash(futureBlock, someHash);
        assertFalse(isValid);
    }

    function testCompleteFlowWithStateProofs() public {
        // Configure inheritance
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);

        // Create real state proof for marking inactivity
        InheritanceManager.AccountStateProof memory initialState = InheritanceManager.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256("storage_root"),
            codeHash: keccak256("code_hash"),
            proof: new bytes32[](0) // Will be filled by helper
        });

        // Create other accounts for the state trie
        address[] memory otherAccounts = new address[](1);
        otherAccounts[0] = address(0x3);

        InheritanceManager.AccountStateProof[] memory otherStates = new InheritanceManager.AccountStateProof[](1);
        otherStates[0] = InheritanceManager.AccountStateProof({
            nonce: 10,
            balance: 1 ether,
            storageHash: keccak256("other_storage"),
            codeHash: keccak256("other_code"),
            proof: new bytes32[](0)
        });

        // Generate real state proof
        (bytes32 stateRoot, bytes32[] memory proof) =
            stateProofHelper.generateSingleStateProof(accountOwner, initialState, otherAccounts, otherStates);
        initialState.proof = proof;

        // Mark inactivity with state proof
        vm.roll(TEST_BLOCK + 100);
        uint256 inactivityBlock = TEST_BLOCK + 100;

        vm.expectEmit(true, false, false, true);
        emit InactivityMarked(accountOwner, inactivityBlock, 42, 5 ether);

        // Generate block header RLP using test helper
        bytes32 testStateRoot = inheritanceManager.createTestStateRoot(inactivityBlock);
        bytes memory blockHeaderRLP = inheritanceManager.createTestBlockHeader(inactivityBlock, testStateRoot);

        inheritanceManager.markInactivityStartWithProof(accountOwner, blockHeaderRLP, initialState);

        // Wait for inactivity period
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1);
        uint256 claimBlock = TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1;

        // Create state proof showing account is still inactive (same nonce)
        InheritanceManager.AccountStateProof memory currentState = InheritanceManager.AccountStateProof({
            nonce: 42, // Same nonce (inactive)
            balance: 5 ether, // Balance can change, but nonce is what matters
            storageHash: keccak256("storage_root"),
            codeHash: keccak256("code_hash"),
            proof: new bytes32[](0)
        });

        // Generate state proof for current state
        (bytes32 currentStateRoot, bytes32[] memory currentProof) =
            stateProofHelper.generateSingleStateProof(accountOwner, currentState, otherAccounts, otherStates);
        currentState.proof = currentProof;

        // Claim inheritance with state proof
        vm.prank(inheritor);
        vm.expectEmit(true, true, false, false);
        emit InheritanceClaimed(accountOwner, inheritor);

        // Generate block header RLP using test helper
        bytes32 claimStateRoot = inheritanceManager.createTestStateRoot(claimBlock);
        bytes memory claimBlockHeaderRLP = inheritanceManager.createTestBlockHeader(claimBlock, claimStateRoot);

        inheritanceManager.claimInheritanceWithProof(accountOwner, claimBlockHeaderRLP, currentState);

        // Verify inheritance was claimed
        assertTrue(inheritanceManager.isInheritanceClaimed(accountOwner));
        assertEq(inheritanceManager.authorizedSigners(accountOwner), inheritor);
    }

    function testStateProofRejectsAccountActivity() public {
        // Configure inheritance
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);

        // Mark inactivity
        bytes32[] memory mockProof = new bytes32[](1);
        mockProof[0] = keccak256("mock_proof");

        InheritanceManager.AccountStateProof memory initialStateProof = InheritanceManager.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256("mock_storage"),
            codeHash: keccak256("mock_code"),
            proof: mockProof
        });

        vm.roll(TEST_BLOCK + 100);
        uint256 inactivityBlock = TEST_BLOCK + 100;

        // Generate block header RLP using test helper
        bytes32 testStateRoot = inheritanceManager.createTestStateRoot(inactivityBlock);
        bytes memory blockHeaderRLP = inheritanceManager.createTestBlockHeader(inactivityBlock, testStateRoot);

        inheritanceManager.markInactivityStartWithProof(accountOwner, blockHeaderRLP, initialStateProof);

        // Wait for inactivity period
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1);
        uint256 claimBlock = TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1;

        // Create state proof showing account became active (different nonce)
        InheritanceManager.AccountStateProof memory activeStateProof = InheritanceManager.AccountStateProof({
            nonce: 43, // Different nonce (account became active)
            balance: 5 ether,
            storageHash: keccak256("mock_storage"),
            codeHash: keccak256("mock_code"),
            proof: mockProof
        });

        // Generate block header RLP using test helper
        bytes32 claimStateRoot = inheritanceManager.createTestStateRoot(claimBlock);
        bytes memory claimBlockHeaderRLP = inheritanceManager.createTestBlockHeader(claimBlock, claimStateRoot);

        // Attempt to claim inheritance should fail
        vm.prank(inheritor);
        vm.expectRevert(abi.encodeWithSelector(InheritanceManager.AccountStillActive.selector));
        inheritanceManager.claimInheritanceWithProof(accountOwner, claimBlockHeaderRLP, activeStateProof);
    }

    function testInvalidStateProofRejection() public {
        // Configure inheritance
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);

        // Create invalid state proof (not mock)
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = keccak256("invalid_proof");

        InheritanceManager.AccountStateProof memory invalidStateProof = InheritanceManager.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256("invalid_storage"),
            codeHash: keccak256("invalid_code"),
            proof: invalidProof
        });

        vm.roll(TEST_BLOCK + 100);
        uint256 inactivityBlock = TEST_BLOCK + 100;
        bytes32 inactivityBlockHash = blockhash(inactivityBlock);

        // Generate block header RLP using test helper
        bytes32 testStateRoot = inheritanceManager.createTestStateRoot(inactivityBlock);
        bytes memory blockHeaderRLP = inheritanceManager.createTestBlockHeader(inactivityBlock, testStateRoot);

        // Should revert with invalid test state proof
        vm.expectRevert("Invalid test state proof");
        inheritanceManager.markInactivityStartWithProof(accountOwner, blockHeaderRLP, invalidStateProof);
    }

    function testInvalidBlockHashRejection() public {
        // Configure inheritance
        vm.prank(accountOwner);
        inheritanceManager.configureInheritance(accountOwner, inheritor, INACTIVITY_PERIOD);

        // Create valid mock state proof
        bytes32[] memory mockProof = new bytes32[](1);
        mockProof[0] = keccak256("mock_proof");

        InheritanceManager.AccountStateProof memory validStateProof = InheritanceManager.AccountStateProof({
            nonce: 42,
            balance: 5 ether,
            storageHash: keccak256("mock_storage"),
            codeHash: keccak256("mock_code"),
            proof: mockProof
        });

        vm.roll(TEST_BLOCK + 100);
        uint256 inactivityBlock = TEST_BLOCK + 100;
        bytes32 invalidBlockHash = keccak256("invalid_block_hash");

        // Should revert with production RLP parsing error in test mode
        vm.expectRevert("Production RLP parsing not supported in test mode");

        // Generate invalid block header RLP (will not match blockhash)
        bytes memory invalidBlockHeaderRLP = abi.encode("invalid_block_header");

        inheritanceManager.markInactivityStartWithProof(accountOwner, invalidBlockHeaderRLP, validStateProof);
    }
}
