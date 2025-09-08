// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title EOAInheritanceLogic
 * @dev Enhanced implementation for EOA inheritance over inactivity using EIP-7702
 * This contract represents the logic that an EOA would execute via EIP-7702
 * to enable and manage inheritance over inactivity.
 * It operates directly on the EOA's storage.
 *
 * Key improvements:
 * - Added events for better tracking
 * - Enhanced security with reentrancy protection
 * - Better error handling and validation
 * - Emergency functions for edge cases
 * - Grace period mechanism
 * - Multiple inheritors support (future extension)
 */
contract EOAInheritanceLogic {

    // --- Events ---
    event InheritanceSetup(address indexed inheritor, uint256 inactivityPeriod);
    event ActivityRecorded(address indexed owner, uint256 timestamp);
    event OwnershipClaimed(address indexed previousOwner, address indexed newOwner);
    event InheritanceCancelled(address indexed owner);
    event EmergencyReset(address indexed owner);

    // --- Custom Errors ---
    error UnauthorizedAccess();
    error InvalidInheritor();
    error InvalidPeriod();
    error InactivityPeriodNotMet();
    error NoInheritanceConfigured();
    error ReentrancyGuard();

    // --- Storage Slot Locations ---
    // We define fixed locations in the EOA's storage to save state.
    // This is how the EOA "remembers" its inheritance settings.
    bytes32 constant INHERITOR_SLOT = keccak256("eip7702.inheritance.inheritor");
    bytes32 constant PERIOD_SLOT = keccak256("eip7702.inheritance.period");
    bytes32 constant LAST_ACTIVE_SLOT = keccak256("eip7702.inheritance.last_active_timestamp");
    bytes32 constant AUTHORIZED_OWNER_SLOT = keccak256("eip7702.inheritance.authorized_owner");
    bytes32 constant REENTRANCY_GUARD_SLOT = keccak256("eip7702.inheritance.reentrancy_guard");
    bytes32 constant GRACE_PERIOD_SLOT = keccak256("eip7702.inheritance.grace_period");

    // --- Constants ---
    uint256 public constant MIN_INACTIVITY_PERIOD = 30 days;
    uint256 public constant MAX_INACTIVITY_PERIOD = 10 * 365 days; // 10 years
    uint256 public constant DEFAULT_GRACE_PERIOD = 7 days;

    // --- Modifiers ---
    modifier onlyAuthorizedOwner() {
        if (msg.sender != _getAuthorizedOwner()) revert UnauthorizedAccess();
        _;
    }

    modifier nonReentrant() {
        if (_getReentrancyGuard()) revert ReentrancyGuard();
        _setReentrancyGuard(true);
        _;
        _setReentrancyGuard(false);
    }

    // --- Main Functions ---

    /**
     * @notice Sets up or updates the inheritance configuration.
     * @dev To be called by the EOA owner through an EIP-7702 transaction.
     * @param _inheritor The address that will inherit the EOA
     * @param _inactivityPeriod The period of inactivity before inheritance can be claimed
     */
    function setupInheritance(address _inheritor, uint256 _inactivityPeriod)
        external
        nonReentrant
    {
        // Initialize owner if not set
        address currentOwner = _getAuthorizedOwner();
        if (currentOwner == address(0)) {
            // In EIP-7702, the EOA delegates to this contract logic
            // msg.sender is the EOA calling this function
            _setAuthorizedOwner(msg.sender);
            currentOwner = msg.sender;
        }

        // Validate caller
        if (msg.sender != currentOwner) revert UnauthorizedAccess();

        // Validate inputs
        if (_inheritor == address(0)) revert InvalidInheritor();
        if (_inheritor == currentOwner) revert InvalidInheritor();
        if (_inactivityPeriod < MIN_INACTIVITY_PERIOD || _inactivityPeriod > MAX_INACTIVITY_PERIOD) {
            revert InvalidPeriod();
        }

        // Store settings
        bytes32 inheritorSlot = INHERITOR_SLOT;
        bytes32 periodSlot = PERIOD_SLOT;
        bytes32 lastActiveSlot = LAST_ACTIVE_SLOT;
        bytes32 gracePeriodSlot = GRACE_PERIOD_SLOT;
        uint256 currentTime = block.timestamp;
        uint256 defaultGrace = DEFAULT_GRACE_PERIOD;

        assembly {
            sstore(inheritorSlot, _inheritor)
            sstore(periodSlot, _inactivityPeriod)
            sstore(lastActiveSlot, currentTime)
            sstore(gracePeriodSlot, defaultGrace)
        }

        emit InheritanceSetup(_inheritor, _inactivityPeriod);
    }

    /**
     * @notice Resets the inactivity timer.
     * @dev The owner calls this to prove they are still active.
     */
    function keepAlive() external onlyAuthorizedOwner nonReentrant {
        bytes32 lastActiveSlot = LAST_ACTIVE_SLOT;
        uint256 currentTime = block.timestamp;

        assembly {
            sstore(lastActiveSlot, currentTime)
        }

        emit ActivityRecorded(msg.sender, block.timestamp);
    }

    /**
     * @notice The inheritor claims ownership after the inactivity period.
     * @dev This function transfers the "authorized ownership" on-chain.
     */
    function claimOwnership() external nonReentrant {
        address inheritor = _getInheritor();
        if (inheritor == address(0)) revert NoInheritanceConfigured();
        if (msg.sender != inheritor) revert UnauthorizedAccess();

        uint256 lastActive = _getLastActiveTimestamp();
        uint256 period = _getInactivityPeriod();
        uint256 gracePeriod = _getGracePeriod();

        // Check if inactivity period + grace period has passed
        if (block.timestamp < lastActive + period + gracePeriod) {
            revert InactivityPeriodNotMet();
        }

        address previousOwner = _getAuthorizedOwner();

        // Transfer ownership
        _setAuthorizedOwner(inheritor);

        // Clean up inheritance settings
        bytes32 inheritorSlot = INHERITOR_SLOT;
        bytes32 periodSlot = PERIOD_SLOT;
        bytes32 gracePeriodSlot = GRACE_PERIOD_SLOT;

        assembly {
            sstore(inheritorSlot, 0)
            sstore(periodSlot, 0)
            sstore(gracePeriodSlot, 0)
        }

        emit OwnershipClaimed(previousOwner, inheritor);
    }

    /**
     * @notice Cancels the inheritance configuration.
     * @dev Only the current owner can cancel inheritance.
     */
    function cancelInheritance() external nonReentrant {
        if (_getInheritor() == address(0)) revert NoInheritanceConfigured();
        if (msg.sender != _getAuthorizedOwner()) revert UnauthorizedAccess();

        // Clear inheritance settings
        bytes32 inheritorSlot = INHERITOR_SLOT;
        bytes32 periodSlot = PERIOD_SLOT;
        bytes32 gracePeriodSlot = GRACE_PERIOD_SLOT;
        bytes32 lastActiveSlot = LAST_ACTIVE_SLOT;
        uint256 currentTime = block.timestamp;

        assembly {
            sstore(inheritorSlot, 0)
            sstore(periodSlot, 0)
            sstore(gracePeriodSlot, 0)
            sstore(lastActiveSlot, currentTime)
        }

        emit InheritanceCancelled(msg.sender);
    }

    /**
     * @notice Emergency reset function for edge cases.
     * @dev Can only be called by the current authorized owner.
     */
    function emergencyReset() external nonReentrant {
        address currentOwner = _getAuthorizedOwner();
        if (currentOwner == address(0) || msg.sender != currentOwner) revert UnauthorizedAccess();

        // Reset all settings
        bytes32 inheritorSlot = INHERITOR_SLOT;
        bytes32 periodSlot = PERIOD_SLOT;
        bytes32 lastActiveSlot = LAST_ACTIVE_SLOT;
        bytes32 gracePeriodSlot = GRACE_PERIOD_SLOT;
        bytes32 authorizedOwnerSlot = AUTHORIZED_OWNER_SLOT;

        assembly {
            sstore(inheritorSlot, 0)
            sstore(periodSlot, 0)
            sstore(lastActiveSlot, 0)
            sstore(gracePeriodSlot, 0)
            sstore(authorizedOwnerSlot, 0)
        }

        emit EmergencyReset(msg.sender);
    }

    // --- View Functions ---

    /**
     * @notice Gets the current inheritance configuration.
     * @return inheritor The configured inheritor address
     * @return inactivityPeriod The inactivity period in seconds
     * @return lastActive The last activity timestamp
     * @return gracePeriod The grace period in seconds
     */
    function getInheritanceConfig()
        external
        view
        returns (
            address inheritor,
            uint256 inactivityPeriod,
            uint256 lastActive,
            uint256 gracePeriod
        )
    {
        return (
            _getInheritor(),
            _getInactivityPeriod(),
            _getLastActiveTimestamp(),
            _getGracePeriod()
        );
    }

    /**
     * @notice Gets the current authorized owner.
     * @return The address of the current authorized owner
     */
    function getAuthorizedOwner() external view returns (address) {
        return _getAuthorizedOwner();
    }

    /**
     * @notice Checks if inheritance can be claimed.
     * @return canClaim Whether inheritance can be claimed
     * @return timeRemaining Time remaining until inheritance can be claimed (0 if can claim)
     */
    function canClaimInheritance() external view returns (bool canClaim, uint256 timeRemaining) {
        address inheritor = _getInheritor();
        if (inheritor == address(0)) {
            return (false, type(uint256).max);
        }

        uint256 lastActive = _getLastActiveTimestamp();
        uint256 period = _getInactivityPeriod();
        uint256 gracePeriod = _getGracePeriod();
        uint256 claimableTime = lastActive + period + gracePeriod;

        if (block.timestamp >= claimableTime) {
            return (true, 0);
        } else {
            return (false, claimableTime - block.timestamp);
        }
    }

    // --- Internal Helper Functions (Read from storage) ---

    function _getAuthorizedOwner() internal view returns (address) {
        bytes32 ownerBytes;
        bytes32 slot = AUTHORIZED_OWNER_SLOT;
        assembly { ownerBytes := sload(slot) }
        return address(uint160(uint256(ownerBytes)));
    }

    function _getInheritor() internal view returns (address) {
        bytes32 inheritorBytes;
        bytes32 slot = INHERITOR_SLOT;
        assembly { inheritorBytes := sload(slot) }
        return address(uint160(uint256(inheritorBytes)));
    }

    function _getInactivityPeriod() internal view returns (uint256) {
        uint256 period;
        bytes32 slot = PERIOD_SLOT;
        assembly { period := sload(slot) }
        return period;
    }

    function _getLastActiveTimestamp() internal view returns (uint256) {
        uint256 ts;
        bytes32 slot = LAST_ACTIVE_SLOT;
        assembly { ts := sload(slot) }
        return ts;
    }

    function _getGracePeriod() internal view returns (uint256) {
        uint256 gracePeriod;
        bytes32 slot = GRACE_PERIOD_SLOT;
        assembly { gracePeriod := sload(slot) }
        return gracePeriod;
    }

    function _getReentrancyGuard() internal view returns (bool) {
        uint256 guard;
        bytes32 slot = REENTRANCY_GUARD_SLOT;
        assembly { guard := sload(slot) }
        return guard == 1;
    }

    // --- Internal Helper Functions (Write to storage) ---

    function _setAuthorizedOwner(address _newOwner) internal {
        bytes32 slot = AUTHORIZED_OWNER_SLOT;
        assembly {
            sstore(slot, _newOwner)
        }
    }

    function _setReentrancyGuard(bool _locked) internal {
        bytes32 slot = REENTRANCY_GUARD_SLOT;
        assembly {
            sstore(slot, _locked)
        }
    }
}
