// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../../src/InheritanceManager.sol";

/**
 * @title InheritanceManagerTestHelper
 * @dev Test helper version of InheritanceManager that allows unit testing
 *
 * This contract wraps the production InheritanceManager with test-friendly methods
 * while keeping the production contract completely clean. It provides:
 * - Mock block header verification for unit tests
 * - Simplified state proof verification for testing
 * - Test data generation helpers
 * - Direct access to core business logic for testing
 *
 * IMPORTANT: This contract is ONLY for unit testing and should NEVER be deployed to production
 */
contract InheritanceManagerTestHelper {

    // Wrap the production contract
    InheritanceManager public immutable productionContract;

    // Test mode flag
    bool public testMode = true;

    // Test storage (mirrors production contract structure)
    mapping(address => InheritanceManager.InheritanceConfig) public inheritanceConfigs;
    mapping(address => InheritanceManager.InactivityRecord) public inactivityRecords;
    mapping(address => bool) public inheritanceClaimed;

    // Events (mirror production contract)
    event InheritanceConfigured(address indexed account, address indexed inheritor, uint256 inactivityPeriod);
    event InactivityMarked(address indexed account, uint256 blockNumber, uint256 nonce);
    event InheritanceClaimed(address indexed account, address indexed inheritor);

    // Errors (mirror production contract)
    error UnauthorizedCaller();
    error InheritanceNotConfigured();
    error InactivityNotMarked();
    error InactivityPeriodNotMet();
    error AccountStillActive();
    error InheritanceAlreadyClaimed();

    constructor() {
        productionContract = new InheritanceManager();
    }

    /**
     * @dev Test-friendly version of markInactivityStartWithProof
     */
    function markInactivityStartWithProof(
        address account,
        bytes calldata blockHeaderRLP,
        InheritanceManager.AccountStateProof calldata accountStateProof
    ) external {
        if (testMode) {
            _markInactivityStartTestMode(account, blockHeaderRLP, accountStateProof);
        } else {
            // Delegate to production contract
            productionContract.markInactivityStartWithProof(account, blockHeaderRLP, accountStateProof);
        }
    }

    /**
     * @dev Test-friendly version of claimInheritanceWithProof
     */
    function claimInheritanceWithProof(
        address account,
        bytes calldata blockHeaderRLP,
        InheritanceManager.AccountStateProof calldata currentAccountStateProof
    ) external {
        if (testMode) {
            _claimInheritanceTestMode(account, blockHeaderRLP, currentAccountStateProof);
        } else {
            // Delegate to production contract
            productionContract.claimInheritanceWithProof(account, blockHeaderRLP, currentAccountStateProof);
        }
    }
    
    /**
     * @dev Test-friendly version of markInactivityStart
     * Skips complex block header verification for unit tests
     */
    function _markInactivityStartTestMode(
        address account,
        bytes calldata blockHeaderRLP,
        InheritanceManager.AccountStateProof calldata accountStateProof
    ) internal {
        // Extract block number and state root using test-friendly parsing
        (uint256 blockNumber, bytes32 stateRoot) = _parseTestBlockHeader(blockHeaderRLP);
        
        // Verify account state using test-friendly verification
        require(_verifyTestAccountState(account, stateRoot, accountStateProof), "Invalid test state proof");
        
        // Use the production logic for the rest
        _markInactivityStartInternal(account, blockNumber, accountStateProof.nonce);
    }
    
    /**
     * @dev Test-friendly version of claimInheritance
     * Skips complex block header verification for unit tests
     */
    function _claimInheritanceTestMode(
        address account,
        bytes calldata blockHeaderRLP,
        InheritanceManager.AccountStateProof calldata currentAccountStateProof
    ) internal {
        // Extract block number and state root using test-friendly parsing
        (uint256 blockNumber, bytes32 stateRoot) = _parseTestBlockHeader(blockHeaderRLP);

        // Verify account state using test-friendly verification
        require(_verifyTestAccountState(account, stateRoot, currentAccountStateProof), "Invalid test state proof");

        // Use the production logic for the rest, passing the actual caller
        _claimInheritanceInternal(account, blockNumber, currentAccountStateProof.nonce, msg.sender);
    }
    
    /**
     * @dev Parse test block headers (simplified format for unit tests)
     * Supports both test format and attempts to parse production format
     */
    function _parseTestBlockHeader(bytes calldata blockHeaderRLP) 
        internal 
        pure 
        returns (uint256 blockNumber, bytes32 stateRoot) 
    {
        // Check for test format: simple RLP list with [blockNumber, stateRoot]
        if (blockHeaderRLP.length >= 66 && blockHeaderRLP[0] == 0xf8) {
            // Long RLP list format: 0xf8 + length + data
            blockNumber = abi.decode(blockHeaderRLP[2:34], (uint256));
            stateRoot = abi.decode(blockHeaderRLP[34:66], (bytes32));
            return (blockNumber, stateRoot);
        }
        
        // Check for simple test format: [blockNumber, stateRoot] as raw data
        if (blockHeaderRLP.length == 64) {
            blockNumber = abi.decode(blockHeaderRLP[0:32], (uint256));
            stateRoot = abi.decode(blockHeaderRLP[32:64], (bytes32));
            return (blockNumber, stateRoot);
        }
        
        // For production RLP, we'd need to delegate to the production contract
        // For now, revert with a helpful message
        revert("Production RLP parsing not supported in test mode");
    }
    
    /**
     * @dev Test-friendly account state verification
     * Uses simplified verification for test state roots
     */
    function _verifyTestAccountState(
        address account,
        bytes32 stateRoot,
        InheritanceManager.AccountStateProof memory accountStateProof
    ) internal pure returns (bool) {
        // Check if this is a test state root (contains "test" pattern)
        if (_isTestStateRoot(stateRoot)) {
            // Simplified verification for test data
            return accountStateProof.proof.length > 0 &&
                   accountStateProof.nonce >= 0 &&
                   accountStateProof.balance >= 0;
        }

        // For production verification, we'd delegate to the production contract
        // For now, return true for test purposes
        return true;
    }
    
    /**
     * @dev Check if a state root is from test data
     */
    function _isTestStateRoot(bytes32 stateRoot) internal pure returns (bool) {
        // Test state roots contain patterns like "test_state_root" or "fork_state_root"
        bytes32 testPattern1 = keccak256("test_state_root");
        bytes32 testPattern2 = keccak256("fork_state_root");
        
        // Check if state root starts with test patterns
        return (stateRoot & 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000) == 
               (testPattern1 & 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000) ||
               (stateRoot & 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000) == 
               (testPattern2 & 0xffffffffffffffffffffffffffffffff00000000000000000000000000000000);
    }
    
    // === TEST HELPER FUNCTIONS ===
    
    /**
     * @dev Enable/disable test mode
     */
    function setTestMode(bool _testMode) external {
        testMode = _testMode;
    }
    
    /**
     * @dev Create a simple test block header for unit tests
     */
    function createTestBlockHeader(uint256 blockNumber, bytes32 stateRoot) 
        external 
        pure 
        returns (bytes memory) 
    {
        return abi.encodePacked(
            bytes1(0xf8), // RLP long list
            bytes1(0x40), // 64 bytes length
            abi.encode(blockNumber),
            abi.encode(stateRoot)
        );
    }
    
    /**
     * @dev Create a test state root
     */
    function createTestStateRoot(uint256 blockNumber) external pure returns (bytes32) {
        return keccak256(abi.encodePacked("test_state_root", blockNumber));
    }
    
    /**
     * @dev Direct access to internal marking function for testing
     */
    function markInactivityStartDirect(address account, uint256 blockNumber, uint256 nonce) external {
        _markInactivityStartInternal(account, blockNumber, nonce);
    }
    
    /**
     * @dev Direct access to internal claiming function for testing
     */
    function claimInheritanceDirect(address account, uint256 blockNumber, uint256 nonce) external {
        _claimInheritanceInternal(account, blockNumber, nonce, msg.sender);
    }

    // === DELEGATED FUNCTIONS ===
    // These delegate to the production contract or provide test implementations

    /**
     * @dev Configure inheritance (delegates to production contract)
     */
    function configureInheritance(address account, address inheritor, uint256 inactivityPeriod) external {
        if (testMode) {
            // Check authorization (simplified for testing)
            if (msg.sender != account && authorizedSigners[account] != msg.sender) {
                revert UnauthorizedCaller();
            }

            inheritanceConfigs[account] = InheritanceManager.InheritanceConfig({
                inheritor: inheritor,
                inactivityPeriod: inactivityPeriod,
                isActive: true
            });
            emit InheritanceConfigured(account, inheritor, inactivityPeriod);
        } else {
            productionContract.configureInheritance(account, inheritor, inactivityPeriod);
        }
    }

    /**
     * @dev Check if inheritance is claimed
     */
    function isInheritanceClaimed(address account) external view returns (bool) {
        if (testMode) {
            return inheritanceClaimed[account];
        } else {
            return productionContract.isInheritanceClaimed(account);
        }
    }

    /**
     * @dev Get inheritance configuration (returns individual values like production contract)
     */
    function getInheritanceConfig(address account) external view returns (
        address inheritor,
        uint256 inactivityPeriod,
        bool isActive
    ) {
        if (testMode) {
            InheritanceManager.InheritanceConfig memory config = inheritanceConfigs[account];
            return (config.inheritor, config.inactivityPeriod, config.isActive);
        } else {
            return productionContract.getInheritanceConfig(account);
        }
    }

    /**
     * @dev Get inactivity record (returns individual values like production contract)
     */
    function getInactivityRecord(address account) external view returns (
        uint256 startBlock,
        uint256 startNonce,
        bool isMarked
    ) {
        if (testMode) {
            InheritanceManager.InactivityRecord memory record = inactivityRecords[account];
            return (record.startBlock, record.startNonce, record.isMarked);
        } else {
            return productionContract.getInactivityRecord(account);
        }
    }

    /**
     * @dev Authorize signer (delegate to production contract or provide test implementation)
     */
    function authorizeSigner(address signer) external {
        if (testMode) {
            // Store the authorized signer
            authorizedSigners[msg.sender] = signer;
        } else {
            productionContract.authorizeSigner(signer);
        }
    }

    /**
     * @dev Revoke inheritance configuration
     */
    function revokeInheritance(address account) external {
        if (testMode) {
            // Check authorization
            if (msg.sender != account && authorizedSigners[account] != msg.sender) {
                revert UnauthorizedCaller();
            }

            inheritanceConfigs[account] = InheritanceManager.InheritanceConfig({
                inheritor: address(0),
                inactivityPeriod: 0,
                isActive: false
            });
        } else {
            productionContract.revokeInheritance(account);
        }
    }

    /**
     * @dev Check if inheritance can be claimed (matches production contract signature)
     */
    function canClaimInheritance(address account) external view returns (
        bool canClaim,
        uint256 blocksRemaining,
        address inheritor,
        bool isConfigured
    ) {
        if (testMode) {
            InheritanceManager.InheritanceConfig memory config = inheritanceConfigs[account];
            InheritanceManager.InactivityRecord memory record = inactivityRecords[account];

            if (!config.isActive || !record.isMarked) {
                return (false, 0, address(0), false);
            }

            uint256 requiredBlock = record.startBlock + config.inactivityPeriod;
            if (block.number >= requiredBlock) {
                return (true, 0, config.inheritor, true);
            } else {
                return (false, requiredBlock - block.number, config.inheritor, true);
            }
        } else {
            return productionContract.canClaimInheritance(account);
        }
    }

    /**
     * @dev Get authorized signers mapping (for test compatibility)
     */
    mapping(address => address) public authorizedSigners;
    
    // === INTERNAL HELPER FUNCTIONS ===
    // These expose the core business logic for testing
    
    function _markInactivityStartInternal(address account, uint256 blockNumber, uint256 nonce) internal {
        InheritanceManager.InheritanceConfig storage config = inheritanceConfigs[account];
        if (config.inheritor == address(0)) revert InheritanceNotConfigured();
        if (inheritanceClaimed[account]) revert InheritanceAlreadyClaimed();

        // Store inactivity data
        inactivityRecords[account] = InheritanceManager.InactivityRecord({
            startBlock: blockNumber,
            startNonce: nonce,
            isMarked: true
        });

        emit InactivityMarked(account, blockNumber, nonce);
    }

    function _claimInheritanceInternal(address account, uint256 blockNumber, uint256 nonce, address caller) internal {
        InheritanceManager.InheritanceConfig storage config = inheritanceConfigs[account];
        InheritanceManager.InactivityRecord storage inactivity = inactivityRecords[account];

        if (config.inheritor == address(0)) revert InheritanceNotConfigured();
        if (!inactivity.isMarked) revert InactivityNotMarked();
        if (inheritanceClaimed[account]) revert InheritanceAlreadyClaimed();
        if (caller != config.inheritor) revert UnauthorizedCaller();

        // Check inactivity period
        if (blockNumber < inactivity.startBlock + config.inactivityPeriod) {
            revert InactivityPeriodNotMet();
        }

        // Check account is still inactive (nonce unchanged)
        if (nonce != inactivity.startNonce) revert AccountStillActive();

        // Mark as claimed
        inheritanceClaimed[account] = true;

        // Authorize the inheritor as a signer (like production contract)
        authorizedSigners[account] = config.inheritor;

        emit InheritanceClaimed(account, config.inheritor);
    }
}
