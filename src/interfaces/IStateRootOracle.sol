// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStateRootOracle
 * @dev Interface for a state root oracle that provides verified Ethereum state roots
 * 
 * This oracle is responsible for:
 * 1. Fetching block headers from Ethereum nodes
 * 2. Verifying block header integrity and authenticity
 * 3. Extracting state roots from verified block headers
 * 4. Providing fraud-proof mechanisms for disputed state roots
 * 
 * PRODUCTION IMPLEMENTATION REQUIREMENTS:
 * 
 * 1. SECURITY:
 *    - Multi-node consensus for block header verification
 *    - Economic incentives for honest reporting
 *    - Slashing conditions for malicious oracles
 *    - Time-delayed finality for fraud proof windows
 * 
 * 2. RELIABILITY:
 *    - Redundant data sources (multiple Ethereum nodes)
 *    - Fallback mechanisms for node failures
 *    - Automatic retry logic with exponential backoff
 *    - Health monitoring and alerting
 * 
 * 3. PERFORMANCE:
 *    - Efficient caching of recent state roots
 *    - Batch processing for multiple requests
 *    - Optimized gas usage for on-chain operations
 *    - Rate limiting to prevent abuse
 * 
 * 4. GOVERNANCE:
 *    - Upgradeable oracle implementation
 *    - Parameter adjustment mechanisms
 *    - Emergency pause functionality
 *    - Transparent operation logs
 */
interface IStateRootOracle {
    
    // --- Events ---
    
    /**
     * @dev Emitted when a new state root is verified and stored
     * @param blockNumber The block number
     * @param blockHash The block hash
     * @param stateRoot The verified state root
     * @param timestamp When the verification occurred
     */
    event StateRootVerified(
        uint256 indexed blockNumber,
        bytes32 indexed blockHash,
        bytes32 stateRoot,
        uint256 timestamp
    );
    
    /**
     * @dev Emitted when a state root is challenged
     * @param blockNumber The challenged block number
     * @param challenger The address that initiated the challenge
     * @param challengeId Unique identifier for the challenge
     */
    event StateRootChallenged(
        uint256 indexed blockNumber,
        address indexed challenger,
        uint256 challengeId
    );
    
    /**
     * @dev Emitted when a challenge is resolved
     * @param challengeId The challenge identifier
     * @param successful Whether the challenge was successful
     * @param newStateRoot The corrected state root (if challenge successful)
     */
    event ChallengeResolved(
        uint256 indexed challengeId,
        bool successful,
        bytes32 newStateRoot
    );
    
    // --- Errors ---
    
    error BlockNotFound(uint256 blockNumber);
    error InvalidBlockHash(uint256 blockNumber, bytes32 providedHash);
    error StateRootNotAvailable(uint256 blockNumber);
    error ChallengeWindowExpired(uint256 blockNumber);
    error InsufficientChallengeBond(uint256 required, uint256 provided);
    error UnauthorizedOracle(address caller);
    
    // --- Core Functions ---
    
    /**
     * @notice Get the verified state root for a specific block
     * @param blockNumber The block number to get state root for
     * @param blockHash The expected block hash for verification
     * @return stateRoot The verified state root
     * @dev Reverts if block hash doesn't match or state root not available
     */
    function getStateRoot(
        uint256 blockNumber,
        bytes32 blockHash
    ) external view returns (bytes32 stateRoot);
    
    /**
     * @notice Check if a state root is valid for the given block
     * @param blockNumber The block number
     * @param blockHash The block hash
     * @param stateRoot The state root to verify
     * @return isValid Whether the state root is valid
     */
    function isValidStateRoot(
        uint256 blockNumber,
        bytes32 blockHash,
        bytes32 stateRoot
    ) external view returns (bool isValid);
    
    /**
     * @notice Request verification of a state root for a specific block
     * @param blockNumber The block number to verify
     * @param blockHash The expected block hash
     * @dev This may trigger async verification if not already cached
     */
    function requestStateRootVerification(
        uint256 blockNumber,
        bytes32 blockHash
    ) external;
    
    /**
     * @notice Submit a verified state root (oracle nodes only)
     * @param blockNumber The block number
     * @param blockHash The block hash
     * @param stateRoot The verified state root
     * @param proof Cryptographic proof of verification
     */
    function submitStateRoot(
        uint256 blockNumber,
        bytes32 blockHash,
        bytes32 stateRoot,
        bytes calldata proof
    ) external;
    
    // --- Challenge System ---
    
    /**
     * @notice Challenge a submitted state root
     * @param blockNumber The block number to challenge
     * @param correctStateRoot The claimed correct state root
     * @param proof Proof that the current state root is incorrect
     * @return challengeId Unique identifier for this challenge
     * @dev Requires challenge bond to prevent spam
     */
    function challengeStateRoot(
        uint256 blockNumber,
        bytes32 correctStateRoot,
        bytes calldata proof
    ) external payable returns (uint256 challengeId);
    
    /**
     * @notice Resolve a challenge after investigation
     * @param challengeId The challenge to resolve
     * @param successful Whether the challenge was valid
     * @param finalStateRoot The final verified state root
     * @dev Only callable by authorized resolvers
     */
    function resolveChallenge(
        uint256 challengeId,
        bool successful,
        bytes32 finalStateRoot
    ) external;
    
    // --- Configuration ---
    
    /**
     * @notice Get the challenge window duration
     * @return duration Time in seconds during which challenges are accepted
     */
    function getChallengeWindow() external view returns (uint256 duration);
    
    /**
     * @notice Get the required challenge bond amount
     * @return amount Amount in wei required to submit a challenge
     */
    function getChallengeBond() external view returns (uint256 amount);
    
    /**
     * @notice Check if a block's state root is still within challenge window
     * @param blockNumber The block number to check
     * @return inWindow Whether challenges are still accepted
     */
    function isInChallengeWindow(uint256 blockNumber) external view returns (bool inWindow);
    
    // --- Status Functions ---
    
    /**
     * @notice Get the latest block number with verified state root
     * @return blockNumber The latest verified block
     */
    function getLatestVerifiedBlock() external view returns (uint256 blockNumber);
    
    /**
     * @notice Check oracle health and availability
     * @return healthy Whether the oracle is operating normally
     * @return lastUpdate Timestamp of last successful update
     */
    function getOracleStatus() external view returns (bool healthy, uint256 lastUpdate);
}
