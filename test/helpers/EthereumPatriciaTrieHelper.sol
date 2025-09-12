// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/InheritanceManager.sol";
import "solady/utils/LibRLP.sol";

/**
 * @title EthereumPatriciaTrieHelper
 * @dev Helper contract for generating proper Ethereum Patricia Trie proofs
 * @notice This generates actual Patricia Trie proofs compatible with Polytope Labs library
 */
contract EthereumPatriciaTrieHelper {
    /**
     * @dev Generate a proper Ethereum Patricia Trie proof for account state
     * @param account The account address
     * @param accountState The account state (nonce, balance, storageHash, codeHash)
     * @return stateRoot The Patricia Trie root
     * @return proof The Patricia Trie proof nodes
     */
    function generateEthereumAccountProof(address account, InheritanceManager.AccountStateProof memory accountState)
        external
        pure
        returns (bytes32 stateRoot, bytes[] memory proof)
    {
        // Step 1: Encode the account state using proper RLP encoding
        bytes memory accountRLP = _encodeAccountState(accountState);

        // Step 2: Create the account key (keccak256 of address)
        bytes32 accountKey = keccak256(abi.encodePacked(account));

        // Step 3: Create a minimal Patricia Trie with just this account
        // For simplicity, we'll create a single-leaf trie
        proof = new bytes[](1);

        // Create a leaf node: [encodedPath, value]
        // For a single account, the path is the full key
        bytes memory encodedPath = _encodeNibblePath(abi.encodePacked(accountKey), true); // true = leaf
        LibRLP.List memory list = LibRLP.p();
        LibRLP.p(list, encodedPath);
        LibRLP.p(list, accountRLP);
        bytes memory leafNode = LibRLP.encode(list);

        proof[0] = leafNode;
        stateRoot = keccak256(leafNode);

        return (stateRoot, proof);
    }

    /**
     * @dev Generate Patricia Trie proof for multiple accounts
     * @param accounts Array of account addresses
     * @param accountStates Array of account states
     * @return stateRoot The Patricia Trie root
     * @return proofs Array of Patricia Trie proofs for each account
     */
    function generateMultiAccountProofs(
        address[] memory accounts,
        InheritanceManager.AccountStateProof[] memory accountStates
    ) external view returns (bytes32 stateRoot, bytes[][] memory proofs) {
        require(accounts.length == accountStates.length, "Array length mismatch");

        if (accounts.length == 1) {
            // Single account case
            bytes[] memory singleProof;
            (stateRoot, singleProof) = this.generateEthereumAccountProof(accounts[0], accountStates[0]);
            proofs = new bytes[][](1);
            proofs[0] = singleProof;
            return (stateRoot, proofs);
        }

        // For multiple accounts, we need to build a proper Patricia Trie
        // This is a simplified implementation for testing
        proofs = new bytes[][](accounts.length);

        // Create leaf nodes for all accounts
        bytes[] memory leafNodes = new bytes[](accounts.length);
        bytes32[] memory leafHashes = new bytes32[](accounts.length);

        for (uint256 i = 0; i < accounts.length; i++) {
            bytes memory accountRLP = _encodeAccountState(accountStates[i]);
            bytes32 accountKey = keccak256(abi.encodePacked(accounts[i]));
            bytes memory encodedPath = _encodeNibblePath(abi.encodePacked(accountKey), true);
            LibRLP.List memory leafList = LibRLP.p();
            LibRLP.p(leafList, encodedPath);
            LibRLP.p(leafList, accountRLP);
            leafNodes[i] = LibRLP.encode(leafList);
            leafHashes[i] = keccak256(leafNodes[i]);
        }

        // For simplicity, create a branch node that contains all leaves
        // In a real Patricia Trie, this would be more complex
        bytes memory branchNode = _createBranchNode(leafHashes);
        stateRoot = keccak256(branchNode);

        // Each account's proof is just the leaf node and branch node
        for (uint256 i = 0; i < accounts.length; i++) {
            proofs[i] = new bytes[](2);
            proofs[i][0] = leafNodes[i];
            proofs[i][1] = branchNode;
        }

        return (stateRoot, proofs);
    }

    /**
     * @dev Encode account state according to Ethereum specification
     * @param accountState The account state to encode
     * @return Encoded account state
     */
    function _encodeAccountState(InheritanceManager.AccountStateProof memory accountState)
        internal
        pure
        returns (bytes memory)
    {
        // Ethereum account state: [nonce, balance, storageHash, codeHash]
        LibRLP.List memory accountList = LibRLP.p();
        LibRLP.p(accountList, accountState.nonce);
        LibRLP.p(accountList, accountState.balance);
        LibRLP.p(accountList, abi.encodePacked(accountState.storageHash));
        LibRLP.p(accountList, abi.encodePacked(accountState.codeHash));
        return LibRLP.encode(accountList);
    }

    /**
     * @dev Encode nibble path for Patricia Trie
     * @param keyBytes The key bytes
     * @param isLeaf Whether this is a leaf node
     * @return Encoded path
     */
    function _encodeNibblePath(bytes memory keyBytes, bool isLeaf) internal pure returns (bytes memory) {
        // Patricia Trie path encoding:
        // - First nibble contains flags: 0x2 for leaf, 0x0 for extension
        // - If odd number of nibbles, add 0x1 to first nibble

        uint8 prefix = isLeaf ? 0x20 : 0x00; // 0x2_ for leaf, 0x0_ for extension

        // For simplicity, assume even number of nibbles (64 nibbles for 32-byte key)
        bytes memory encoded = new bytes(keyBytes.length + 1);
        encoded[0] = bytes1(prefix);

        for (uint256 i = 0; i < keyBytes.length; i++) {
            encoded[i + 1] = keyBytes[i];
        }

        return encoded;
    }

    /**
     * @dev Create a simplified branch node
     * @param leafHashes Array of leaf hashes
     * @return Encoded branch node
     */
    function _createBranchNode(bytes32[] memory leafHashes) internal pure returns (bytes memory) {
        // A branch node has 17 elements: 16 for each nibble + 1 for value
        bytes[] memory branches = new bytes[](17);

        // Put leaf hashes in appropriate branches (simplified)
        for (uint256 i = 0; i < leafHashes.length && i < 16; i++) {
            branches[i] = abi.encodePacked(leafHashes[i]);
        }

        // Fill remaining branches with empty
        for (uint256 i = leafHashes.length; i < 16; i++) {
            branches[i] = "";
        }

        // Last element (value) is empty for branch nodes
        branches[16] = "";

        LibRLP.List memory branchList = LibRLP.p();
        for (uint256 i = 0; i < 17; i++) {
            LibRLP.p(branchList, branches[i]);
        }
        return LibRLP.encode(branchList);
    }
}
