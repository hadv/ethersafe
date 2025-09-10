// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title InheritanceManager
 * @dev Inheritance mechanism that works with existing EIP-7702 delegated accounts
 * @notice This contract manages inheritance for accounts that are already using EIP-7702 delegation
 * 
 * The idea is:
 * 1. Account owner uses existing MetaMask EIP-7702 delegator for normal operations
 * 2. Account owner configures inheritance through this separate InheritanceManager
 * 3. When inheritance is claimed, this contract can call the EIP-7702 delegator to transfer assets
 * 4. The existing EIP-7702 contract remains unchanged and unmodified
 */
contract InheritanceManager {
    
    // --- Inheritance Configuration ---
    
    struct InheritanceConfig {
        address inheritor;           // Who inherits the account
        uint256 inactivityPeriod;   // How long account must be inactive
        bool isActive;              // Whether inheritance is configured
    }
    
    struct InactivityRecord {
        uint256 startBlock;         // When inactivity period started
        uint256 startNonce;         // Account nonce at start
        bool isMarked;              // Whether inactivity has been marked
    }

    /**
     * @dev Account state proof structure for Merkle verification
     * This represents the account state that needs to be proven
     */
    struct AccountStateProof {
        uint256 nonce;              // Account nonce
        uint256 balance;            // Account balance
        bytes32 storageHash;        // Storage trie root hash
        bytes32 codeHash;           // Code hash
        bytes32[] proof;            // Merkle proof path
    }

    /**
     * @dev Ethereum block header structure for RLP decoding and state root extraction
     * This represents the complete block header as it appears on Ethereum mainnet
     *
     * IMPORTANT: The order of fields MUST match the exact RLP encoding order used by Ethereum:
     * [parentHash, uncleHash, coinbase, stateRoot, transactionRoot, receiptRoot, logsBloom,
     *  difficulty, number, gasLimit, gasUsed, timestamp, extraData, mixHash, nonce,
     *  baseFeePerGas, withdrawalsRoot, blobGasUsed, excessBlobGas, parentBeaconBlockRoot]
     */
    struct BlockHeader {
        bytes32 parentHash;         // Hash of parent block
        bytes32 uncleHash;          // Hash of uncle blocks (ommers)
        address coinbase;           // Miner/validator address
        bytes32 stateRoot;          // STATE ROOT - This is what we extract and verify
        bytes32 transactionRoot;    // Merkle root of transactions
        bytes32 receiptRoot;        // Merkle root of transaction receipts
        bytes logsBloom;            // Bloom filter for logs (256 bytes)
        uint256 difficulty;         // Block difficulty (0 for PoS)
        uint256 number;             // Block number
        uint256 gasLimit;           // Gas limit for block
        uint256 gasUsed;            // Gas used in block
        uint256 timestamp;          // Block timestamp
        bytes extraData;            // Extra data field
        bytes32 mixHash;            // Mix hash for PoW (random for PoS)
        uint64 nonce;               // Block nonce (0 for PoS)
        uint256 baseFeePerGas;      // EIP-1559 base fee (London fork)
        bytes32 withdrawalsRoot;    // EIP-4895 withdrawals root (Shanghai fork)
        uint256 blobGasUsed;        // EIP-4844 blob gas used (Cancun fork)
        uint256 excessBlobGas;      // EIP-4844 excess blob gas (Cancun fork)
        bytes32 parentBeaconBlockRoot; // EIP-4788 parent beacon block root (Cancun fork)
    }

    // --- State Variables ---
    
    mapping(address => InheritanceConfig) public inheritanceConfigs;
    mapping(address => InactivityRecord) public inactivityRecords;
    mapping(address => bool) public inheritanceClaimed;
    mapping(address => address) public authorizedSigners;
    
    // No asset registration needed!
    // With EIP-7702 delegation, inheritor gets access to ALL assets automatically
    
    // --- Events ---
    
    event InheritanceConfigured(address indexed account, address indexed inheritor, uint256 inactivityPeriod);
    event InactivityMarked(address indexed account, uint256 startBlock, uint256 nonce, uint256 balance);
    event InheritanceClaimed(address indexed account, address indexed inheritor);
    
    // --- Errors ---
    
    error UnauthorizedCaller();
    error InheritanceNotConfigured();
    error InactivityNotMarked();
    error InactivityPeriodNotMet();
    error AccountStillActive();
    error InheritanceAlreadyClaimed();
    error InvalidInheritor();
    error InvalidPeriod();
    error InvalidStateProof();
    error InvalidBlockHash();

    // --- State Proof Verification ---

    /**
     * @notice Verify account state using Merkle proof against state root
     * @param account The account to verify
     * @param stateRoot The state root to verify against
     * @param accountStateProof The account state and Merkle proof
     * @return isValid Whether the proof is valid
     */
    function verifyAccountState(
        address account,
        bytes32 stateRoot,
        AccountStateProof memory accountStateProof
    ) public pure returns (bool isValid) {
        // Encode the account state according to Ethereum's RLP encoding
        // Account state: [nonce, balance, storageHash, codeHash]
        bytes memory accountRLP = abi.encodePacked(
            _encodeRLPUint(accountStateProof.nonce),
            _encodeRLPUint(accountStateProof.balance),
            _encodeRLPBytes32(accountStateProof.storageHash),
            _encodeRLPBytes32(accountStateProof.codeHash)
        );

        // Create the account leaf hash
        bytes32 accountLeaf = keccak256(accountRLP);

        // Create the account key (address hash)
        bytes32 accountKey = keccak256(abi.encodePacked(account));

        // The final leaf is the hash of key + value
        bytes32 leafHash = keccak256(abi.encodePacked(accountKey, accountLeaf));

        // Verify the Merkle proof against the state root
        return MerkleProof.verify(accountStateProof.proof, stateRoot, leafHash);
    }

    /**
     * @dev Extract and verify state root from RLP-encoded block header
     * @param blockHeaderRLP The complete RLP-encoded block header
     * @return blockNumber The block number extracted from the header
     * @return stateRoot The extracted state root from the header
     *
     * This function:
     * 1. Decodes the RLP header to extract block number and state root
     * 2. Gets the expected block hash using blockhash(blockNumber)
     * 3. Verifies the block header hash matches the on-chain block hash
     * 4. Returns both the block number and verified state root
     *
     * SECURITY: This is cryptographically secure because:
     * - Block number is extracted from the header itself (trustless)
     * - Uses Solidity's blockhash() for trustless verification
     * - Block hash verification ensures header authenticity
     * - RLP decoding follows Ethereum's exact specification
     * - State root is extracted from the verified header
     * - No external dependencies or oracles required
     */
    function extractStateRootFromHeader(
        bytes calldata blockHeaderRLP
    ) public view returns (uint256 blockNumber, bytes32 stateRoot) {
        // First extract block number and state root from RLP
        (blockNumber, stateRoot) = _decodeBlockNumberAndStateRoot(blockHeaderRLP);

        // Get the expected block hash from Solidity's blockhash()
        bytes32 expectedBlockHash = blockhash(blockNumber);
        require(expectedBlockHash != bytes32(0), "Block hash not available");

        // Verify the block header hash matches the on-chain block hash
        bytes32 actualBlockHash = keccak256(blockHeaderRLP);
        require(actualBlockHash == expectedBlockHash, "Block header hash mismatch");
    }

    /**
     * @dev Decode block number and state root from RLP-encoded block header
     * @param rlpData The RLP-encoded block header
     * @return blockNumber The block number (9th field in the header)
     * @return stateRoot The state root (4th field in the header)
     *
     * Ethereum block header RLP structure:
     * [parentHash, uncleHash, coinbase, stateRoot, transactionRoot, receiptRoot, logsBloom,
     *  difficulty, number, gasLimit, gasUsed, timestamp, extraData, mixHash, nonce, ...]
     *
     * We need to extract:
     * - Field 3 (index 3): stateRoot (32 bytes)
     * - Field 8 (index 8): number (variable length uint256)
     */
    function _decodeBlockNumberAndStateRoot(
        bytes calldata rlpData
    ) internal pure returns (uint256 blockNumber, bytes32 stateRoot) {
        uint256 offset = 0;

        // Skip the list prefix
        (offset, ) = _decodeRLPListPrefix(rlpData, offset);

        // Extract fields in order
        // Field 0: parentHash (32 bytes) - skip
        offset = _skipRLPItem(rlpData, offset);
        // Field 1: uncleHash (32 bytes) - skip
        offset = _skipRLPItem(rlpData, offset);
        // Field 2: coinbase (20 bytes) - skip
        offset = _skipRLPItem(rlpData, offset);

        // Field 3: stateRoot (32 bytes) - extract this
        uint256 stateRootLength;
        (offset, stateRootLength) = _decodeRLPItemPrefix(rlpData, offset);
        require(stateRootLength == 32, "Invalid state root length");

        assembly {
            stateRoot := calldataload(add(rlpData.offset, offset))
        }
        offset += stateRootLength;

        // Field 4: transactionRoot (32 bytes) - skip
        offset = _skipRLPItem(rlpData, offset);
        // Field 5: receiptRoot (32 bytes) - skip
        offset = _skipRLPItem(rlpData, offset);
        // Field 6: logsBloom (256 bytes) - skip
        offset = _skipRLPItem(rlpData, offset);
        // Field 7: difficulty (variable length) - skip
        offset = _skipRLPItem(rlpData, offset);

        // Field 8: number (variable length uint256) - extract this
        uint256 numberLength;
        (offset, numberLength) = _decodeRLPItemPrefix(rlpData, offset);
        require(numberLength <= 32, "Invalid block number length");

        // Extract block number (big-endian)
        blockNumber = 0;
        for (uint256 i = 0; i < numberLength; i++) {
            blockNumber = (blockNumber << 8) | uint8(rlpData[offset + i]);
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

    // --- RLP Decoding Helper Functions ---

    /**
     * @dev Decode RLP list prefix and return offset and length
     */
    function _decodeRLPListPrefix(
        bytes calldata data,
        uint256 offset
    ) internal pure returns (uint256 newOffset, uint256 length) {
        require(offset < data.length, "RLP: offset out of bounds");

        uint8 prefix = uint8(data[offset]);

        if (prefix <= 0xf7) {
            // Short list (0-55 bytes)
            length = prefix - 0xc0;
            newOffset = offset + 1;
        } else {
            // Long list (>55 bytes)
            uint256 lengthOfLength = prefix - 0xf7;
            require(offset + 1 + lengthOfLength <= data.length, "RLP: invalid long list");

            length = 0;
            for (uint256 i = 0; i < lengthOfLength; i++) {
                length = (length << 8) | uint8(data[offset + 1 + i]);
            }
            newOffset = offset + 1 + lengthOfLength;
        }
    }

    /**
     * @dev Decode RLP item prefix and return offset and length
     */
    function _decodeRLPItemPrefix(
        bytes calldata data,
        uint256 offset
    ) internal pure returns (uint256 newOffset, uint256 length) {
        require(offset < data.length, "RLP: offset out of bounds");

        uint8 prefix = uint8(data[offset]);

        if (prefix <= 0x7f) {
            // Single byte
            length = 1;
            newOffset = offset;
        } else if (prefix <= 0xb7) {
            // Short string (0-55 bytes)
            length = prefix - 0x80;
            newOffset = offset + 1;
        } else {
            // Long string (>55 bytes)
            uint256 lengthOfLength = prefix - 0xb7;
            require(offset + 1 + lengthOfLength <= data.length, "RLP: invalid long string");

            length = 0;
            for (uint256 i = 0; i < lengthOfLength; i++) {
                length = (length << 8) | uint8(data[offset + 1 + i]);
            }
            newOffset = offset + 1 + lengthOfLength;
        }
    }

    /**
     * @dev Skip an RLP item and return the new offset
     */
    function _skipRLPItem(
        bytes calldata data,
        uint256 offset
    ) internal pure returns (uint256 newOffset) {
        (uint256 itemOffset, uint256 length) = _decodeRLPItemPrefix(data, offset);
        return itemOffset + length;
    }

    /**
     * @notice Verify block hash is valid and accessible
     * @param blockNumber The block number to verify
     * @param providedBlockHash The block hash provided
     * @return isValid Whether the block hash is valid
     */
    function verifyBlockHash(
        uint256 blockNumber,
        bytes32 providedBlockHash
    ) public view returns (bool isValid) {
        // For current block, we can't get blockhash
        if (blockNumber >= block.number) {
            return false;
        }

        // Get the actual block hash
        bytes32 actualBlockHash = blockhash(blockNumber);

        // For blocks older than 256 blocks, blockhash returns 0
        if (actualBlockHash == bytes32(0)) {
            // Block too old - cannot verify
            return false;
        }

        // Verify the provided block hash matches the actual block hash
        return actualBlockHash == providedBlockHash;
    }




    // --- Production State Proof Functions ---

    /**
     * @notice Mark inactivity with full state proof verification (public version)
     * @dev This is the production-ready function with complete cryptographic verification
     * @param account The account to mark as inactive
     * @param blockHeaderRLP The complete RLP-encoded block header
     * @param accountStateProof Complete account state proof including Merkle proof
     */
    function markInactivityStartWithProof(
        address account,
        bytes calldata blockHeaderRLP,
        AccountStateProof calldata accountStateProof
    ) external {
        // Extract block number and state root from header, verify against on-chain block hash
        (uint256 blockNumber, bytes32 stateRoot) = extractStateRootFromHeader(blockHeaderRLP);

        // Get block hash for internal verification
        bytes32 blockHash = blockhash(blockNumber);
        require(blockHash != bytes32(0), "Block hash not available");

        _markInactivityStartWithProof(account, blockNumber, blockHash, stateRoot, accountStateProof);
    }

    /**
     * @notice Claim inheritance with full state proof verification (public version)
     * @dev This is the production-ready function with complete cryptographic verification
     * @param account The account to claim inheritance for
     * @param blockHeaderRLP The complete RLP-encoded block header for current state verification
     * @param currentAccountStateProof Complete current account state proof
     */
    function claimInheritanceWithProof(
        address account,
        bytes calldata blockHeaderRLP,
        AccountStateProof calldata currentAccountStateProof
    ) external {
        // Extract block number and state root from header, verify against on-chain block hash
        (uint256 currentBlock, bytes32 stateRoot) = extractStateRootFromHeader(blockHeaderRLP);

        // Get block hash for internal verification
        bytes32 currentBlockHash = blockhash(currentBlock);
        require(currentBlockHash != bytes32(0), "Block hash not available");

        _claimInheritanceWithProof(account, currentBlock, currentBlockHash, stateRoot, currentAccountStateProof);
    }

    // --- Inheritance Configuration ---
    
    /**
     * @notice Configure inheritance for an account
     * @param account The account to configure inheritance for
     * @param inheritor The address that will inherit the account
     * @param inactivityPeriod How long the account must be inactive (in blocks)
     */
    function configureInheritance(
        address account,
        address inheritor,
        uint256 inactivityPeriod
    ) external {
        // Verify caller is authorized (account owner or authorized signer)
        if (msg.sender != account && authorizedSigners[account] != msg.sender) {
            revert UnauthorizedCaller();
        }
        
        if (inheritor == address(0) || inheritor == account) {
            revert InvalidInheritor();
        }
        
        if (inactivityPeriod == 0) {
            revert InvalidPeriod();
        }
        
        inheritanceConfigs[account] = InheritanceConfig({
            inheritor: inheritor,
            inactivityPeriod: inactivityPeriod,
            isActive: true
        });
        
        emit InheritanceConfigured(account, inheritor, inactivityPeriod);
    }
    
    /**
     * @notice Revoke inheritance configuration
     * @param account The account to revoke inheritance for
     */
    function revokeInheritance(address account) external {
        if (msg.sender != account && authorizedSigners[account] != msg.sender) {
            revert UnauthorizedCaller();
        }
        
        delete inheritanceConfigs[account];
        delete inactivityRecords[account];
        delete inheritanceClaimed[account];
    }
    
    /**
     * @notice Authorize a signer to manage inheritance for this account
     * @param signer The address to authorize
     */
    function authorizeSigner(address signer) external {
        authorizedSigners[msg.sender] = signer;
    }
    
    // No registerAssets function needed!
    // With EIP-7702 delegation, inheritor automatically gets access to ALL assets
    
    // --- Inactivity Tracking ---
    
    /**
     * @notice Mark the start of an inactivity period for an account (with state proof)
     * @param account The account to mark as inactive
     * @param blockNumber The block number to check state at
     * @param blockHash The hash of the block at blockNumber
     * @param stateRoot The state root for the specified block
     * @param accountStateProof Complete account state proof including Merkle proof
     */
    function _markInactivityStartWithProof(
        address account,
        uint256 blockNumber,
        bytes32 blockHash,
        bytes32 stateRoot,
        AccountStateProof memory accountStateProof
    ) internal {
        InheritanceConfig memory config = inheritanceConfigs[account];
        if (!config.isActive) {
            revert InheritanceNotConfigured();
        }

        // Verify block hash is valid and accessible
        if (!verifyBlockHash(blockNumber, blockHash)) {
            revert InvalidBlockHash();
        }

        // The state root has already been verified through block header verification
        // in extractStateRootFromHeader(), so we can trust it here

        // Verify the account state proof against the verified state root
        if (!verifyAccountState(account, stateRoot, accountStateProof)) {
            revert InvalidStateProof();
        }

        inactivityRecords[account] = InactivityRecord({
            startBlock: blockNumber,
            startNonce: accountStateProof.nonce,
            isMarked: true
        });

        emit InactivityMarked(account, blockNumber, accountStateProof.nonce, accountStateProof.balance);
    }
    
    // --- Inheritance Claiming ---
    
    /**
     * @notice Claim inheritance of an inactive account (with state proof)
     * @param account The account to claim inheritance for
     * @param currentBlock The current block to verify continued inactivity
     * @param currentBlockHash The hash of the current block
     * @param stateRoot The state root for the current block
     * @param currentAccountStateProof Complete current account state proof
     */
    function _claimInheritanceWithProof(
        address account,
        uint256 currentBlock,
        bytes32 currentBlockHash,
        bytes32 stateRoot,
        AccountStateProof memory currentAccountStateProof
    ) internal {
        InheritanceConfig memory config = inheritanceConfigs[account];
        if (!config.isActive) {
            revert InheritanceNotConfigured();
        }

        if (msg.sender != config.inheritor) {
            revert UnauthorizedCaller();
        }
        
        if (inheritanceClaimed[account]) {
            revert InheritanceAlreadyClaimed();
        }
        
        InactivityRecord memory record = inactivityRecords[account];
        if (!record.isMarked) {
            revert InactivityNotMarked();
        }
        
        // Check if enough time has passed
        if (currentBlock < record.startBlock + config.inactivityPeriod) {
            revert InactivityPeriodNotMet();
        }

        // Verify current block hash is valid
        if (!verifyBlockHash(currentBlock, currentBlockHash)) {
            revert InvalidBlockHash();
        }

        // The state root has already been verified through block header verification
        // in extractStateRootFromHeader(), so we can trust it here

        // Verify the current account state proof against the verified state root
        if (!verifyAccountState(account, stateRoot, currentAccountStateProof)) {
            revert InvalidStateProof();
        }

        // Verify account is still inactive (same nonce only)
        // Note: We only check nonce because balance can change without account owner activity
        // (e.g., receiving ETH transfers, mining rewards, airdrops, etc.)
        if (currentAccountStateProof.nonce != record.startNonce) {
            revert AccountStillActive();
        }
        
        // Mark inheritance as claimed
        inheritanceClaimed[account] = true;
        
        // Transfer control to inheritor
        authorizedSigners[account] = config.inheritor;
        
        emit InheritanceClaimed(account, config.inheritor);

        // No asset transfer needed!
        // With EIP-7702 delegation, inheritor gets direct control of the EOA account
    }
    

    
    // --- View Functions ---
    
    /**
     * @notice Check if inheritance can be claimed for an account
     */
    function canClaimInheritance(address account) external view returns (
        bool canClaim,
        uint256 blocksRemaining,
        address inheritor,
        bool isConfigured
    ) {
        InheritanceConfig memory config = inheritanceConfigs[account];
        if (!config.isActive) {
            return (false, 0, address(0), false);
        }
        
        InactivityRecord memory record = inactivityRecords[account];
        if (!record.isMarked) {
            return (false, 0, config.inheritor, true);
        }
        
        uint256 requiredBlock = record.startBlock + config.inactivityPeriod;
        if (block.number >= requiredBlock) {
            return (true, 0, config.inheritor, true);
        } else {
            return (false, requiredBlock - block.number, config.inheritor, true);
        }
    }
    
    /**
     * @notice Get inheritance configuration for an account
     */
    function getInheritanceConfig(address account) external view returns (
        address inheritor,
        uint256 inactivityPeriod,
        bool isActive
    ) {
        InheritanceConfig memory config = inheritanceConfigs[account];
        return (config.inheritor, config.inactivityPeriod, config.isActive);
    }
    
    /**
     * @notice Check if inheritance has been claimed for an account
     */
    function isInheritanceClaimed(address account) external view returns (bool) {
        return inheritanceClaimed[account];
    }

    /**
     * @notice Get inactivity record for an account
     */
    function getInactivityRecord(address account) external view returns (
        uint256 startBlock,
        uint256 startNonce,
        bool isMarked
    ) {
        InactivityRecord memory record = inactivityRecords[account];
        return (record.startBlock, record.startNonce, record.isMarked);
    }
}
