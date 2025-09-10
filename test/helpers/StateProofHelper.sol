// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../../src/InheritanceManager.sol";

/**
 * @title StateProofHelper
 * @dev Helper contract for generating real state proofs in tests
 */
contract StateProofHelper {
    using MerkleProof for bytes32[];

    /**
     * @dev Generate a real state root and proof for testing
     * @param accounts Array of account addresses
     * @param accountStates Array of account states corresponding to addresses
     * @return stateRoot The generated state root
     * @return proofs Array of Merkle proofs for each account
     */
    function generateStateProofs(
        address[] memory accounts,
        InheritanceManager.AccountStateProof[] memory accountStates
    ) external pure returns (
        bytes32 stateRoot,
        bytes32[][] memory proofs
    ) {
        return _generateStateProofsInternal(accounts, accountStates);
    }

    function _generateStateProofsInternal(
        address[] memory accounts,
        InheritanceManager.AccountStateProof[] memory accountStates
    ) internal pure returns (
        bytes32 stateRoot,
        bytes32[][] memory proofs
    ) {
        require(accounts.length == accountStates.length, "Array length mismatch");

        // Create leaves for the Merkle tree
        bytes32[] memory leaves = new bytes32[](accounts.length);

        for (uint256 i = 0; i < accounts.length; i++) {
            leaves[i] = _createAccountLeaf(accounts[i], accountStates[i]);
        }

        // Build Merkle tree and generate proofs
        (stateRoot, proofs) = _buildMerkleTree(leaves);
    }

    /**
     * @dev Generate a single account state proof
     * @param targetAccount The account to generate proof for
     * @param targetState The state of the target account
     * @param otherAccounts Other accounts in the state trie
     * @param otherStates States of other accounts
     * @return stateRoot The state root
     * @return proof The Merkle proof for the target account
     */
    function generateSingleStateProof(
        address targetAccount,
        InheritanceManager.AccountStateProof memory targetState,
        address[] memory otherAccounts,
        InheritanceManager.AccountStateProof[] memory otherStates
    ) external pure returns (
        bytes32 stateRoot,
        bytes32[] memory proof
    ) {
        // Combine target with other accounts
        address[] memory allAccounts = new address[](otherAccounts.length + 1);
        InheritanceManager.AccountStateProof[] memory allStates = 
            new InheritanceManager.AccountStateProof[](otherStates.length + 1);
        
        allAccounts[0] = targetAccount;
        allStates[0] = targetState;
        
        for (uint256 i = 0; i < otherAccounts.length; i++) {
            allAccounts[i + 1] = otherAccounts[i];
            allStates[i + 1] = otherStates[i];
        }
        
        bytes32[][] memory allProofs;
        (stateRoot, allProofs) = _generateStateProofsInternal(allAccounts, allStates);
        proof = allProofs[0]; // Return proof for target account (index 0)
    }

    /**
     * @dev Create account leaf hash according to Ethereum's state trie format
     */
    function _createAccountLeaf(
        address account,
        InheritanceManager.AccountStateProof memory accountState
    ) internal pure returns (bytes32) {
        // Encode the account state according to Ethereum's RLP encoding
        bytes memory accountRLP = abi.encodePacked(
            _encodeRLPUint(accountState.nonce),
            _encodeRLPUint(accountState.balance),
            _encodeRLPBytes32(accountState.storageHash),
            _encodeRLPBytes32(accountState.codeHash)
        );
        
        // Create the account leaf hash
        bytes32 accountLeaf = keccak256(accountRLP);
        
        // Create the account key (address hash)
        bytes32 accountKey = keccak256(abi.encodePacked(account));
        
        // The final leaf is the hash of key + value
        return keccak256(abi.encodePacked(accountKey, accountLeaf));
    }

    /**
     * @dev Build a simple Merkle tree and generate proofs
     * @param leaves The leaves of the tree
     * @return root The Merkle root
     * @return proofs Array of proofs for each leaf
     */
    function _buildMerkleTree(
        bytes32[] memory leaves
    ) internal pure returns (
        bytes32 root,
        bytes32[][] memory proofs
    ) {
        uint256 n = leaves.length;
        require(n > 0, "No leaves provided");
        
        // For simplicity, we'll create a balanced binary tree
        // In a real implementation, this would follow Ethereum's Patricia Merkle Trie
        
        if (n == 1) {
            root = leaves[0];
            proofs = new bytes32[][](1);
            proofs[0] = new bytes32[](0); // Empty proof for single leaf
            return (root, proofs);
        }
        
        // Build tree level by level
        bytes32[] memory currentLevel = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            currentLevel[i] = leaves[i];
        }
        
        // Store all levels for proof generation
        bytes32[][] memory levels = new bytes32[][](32); // Max 32 levels
        uint256 levelCount = 0;
        
        while (currentLevel.length > 1) {
            levels[levelCount] = currentLevel;
            levelCount++;
            
            uint256 nextLevelSize = (currentLevel.length + 1) / 2;
            bytes32[] memory nextLevel = new bytes32[](nextLevelSize);
            
            for (uint256 i = 0; i < nextLevelSize; i++) {
                if (i * 2 + 1 < currentLevel.length) {
                    // Hash two children
                    nextLevel[i] = keccak256(abi.encodePacked(
                        currentLevel[i * 2],
                        currentLevel[i * 2 + 1]
                    ));
                } else {
                    // Odd number of nodes, promote the last one
                    nextLevel[i] = currentLevel[i * 2];
                }
            }
            
            currentLevel = nextLevel;
        }
        
        root = currentLevel[0];
        
        // Generate proofs for each original leaf
        proofs = new bytes32[][](n);
        for (uint256 leafIndex = 0; leafIndex < n; leafIndex++) {
            proofs[leafIndex] = _generateProofForLeaf(levels, levelCount, leafIndex);
        }
    }

    /**
     * @dev Generate proof for a specific leaf
     */
    function _generateProofForLeaf(
        bytes32[][] memory levels,
        uint256 levelCount,
        uint256 leafIndex
    ) internal pure returns (bytes32[] memory proof) {
        bytes32[] memory proofElements = new bytes32[](levelCount);
        uint256 proofLength = 0;
        uint256 currentIndex = leafIndex;
        
        for (uint256 level = 0; level < levelCount; level++) {
            uint256 siblingIndex;
            if (currentIndex % 2 == 0) {
                // Current node is left child, sibling is right
                siblingIndex = currentIndex + 1;
            } else {
                // Current node is right child, sibling is left
                siblingIndex = currentIndex - 1;
            }
            
            if (siblingIndex < levels[level].length) {
                proofElements[proofLength] = levels[level][siblingIndex];
                proofLength++;
            }
            
            currentIndex = currentIndex / 2;
        }
        
        // Trim proof to actual length
        proof = new bytes32[](proofLength);
        for (uint256 i = 0; i < proofLength; i++) {
            proof[i] = proofElements[i];
        }
    }

    /**
     * @dev Simple RLP encoding for uint256 values
     */
    function _encodeRLPUint(uint256 value) private pure returns (bytes memory) {
        if (value == 0) {
            return hex"80"; // RLP encoding of 0
        }
        
        // Convert to bytes and remove leading zeros
        bytes memory valueBytes = abi.encodePacked(value);
        uint256 leadingZeros = 0;
        for (uint256 i = 0; i < valueBytes.length; i++) {
            if (valueBytes[i] != 0) break;
            leadingZeros++;
        }
        
        bytes memory trimmed = new bytes(valueBytes.length - leadingZeros);
        for (uint256 i = 0; i < trimmed.length; i++) {
            trimmed[i] = valueBytes[leadingZeros + i];
        }
        
        // Add RLP length prefix
        if (trimmed.length == 1 && uint8(trimmed[0]) < 0x80) {
            return trimmed; // Single byte < 0x80 is encoded as itself
        } else if (trimmed.length <= 55) {
            return abi.encodePacked(uint8(0x80 + trimmed.length), trimmed);
        } else {
            bytes memory lengthBytes = abi.encodePacked(trimmed.length);
            return abi.encodePacked(uint8(0xb7 + lengthBytes.length), lengthBytes, trimmed);
        }
    }

    /**
     * @dev Simple RLP encoding for bytes32 values
     */
    function _encodeRLPBytes32(bytes32 value) private pure returns (bytes memory) {
        return abi.encodePacked(uint8(0xa0), value); // 0xa0 = 0x80 + 32
    }

    /**
     * @dev Get current block hash for testing (within 256 block limit)
     */
    function getCurrentBlockHash() external view returns (bytes32) {
        return blockhash(block.number - 1);
    }

    /**
     * @dev Get block hash for a specific block number
     */
    function getBlockHash(uint256 blockNumber) external view returns (bytes32) {
        return blockhash(blockNumber);
    }
}
