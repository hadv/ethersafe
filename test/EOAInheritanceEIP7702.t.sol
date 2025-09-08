// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {EOAInheritanceLogic} from "../src/EOAInheritanceLogic.sol";
import {EOAController} from "../src/EOAController.sol";
import {MockERC20} from "../src/MockERC20.sol";

/**
 * @title EOAInheritanceEIP7702Test
 * @dev Tests for EOA inheritance using actual EIP-7702 delegation
 * This test suite simulates real EOA behavior with delegation
 */
contract EOAInheritanceEIP7702Test is Test {
    EOAInheritanceLogic public inheritanceLogic;
    EOAController public eoaController;
    
    // EOA accounts with private keys
    uint256 public constant EOA_PRIVATE_KEY = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    uint256 public constant INHERITOR_PRIVATE_KEY = 0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;
    uint256 public constant RANDOM_PRIVATE_KEY = 0x9876543210fedcba9876543210fedcba9876543210fedcba9876543210fedcba;
    
    address payable public eoaOwner;
    address payable public inheritor;
    address payable public randomUser;
    
    uint256 public constant VALID_PERIOD = 60 days;
    uint256 public constant GRACE_PERIOD = 7 days;

    // Test target contract for EOA to interact with
    TestTarget public testTarget;
    MockERC20 public mockToken;

    // Events for testing
    event InheritanceSetup(address indexed inheritor, uint256 inactivityPeriod);
    event OwnershipClaimed(address indexed previousOwner, address indexed newOwner);
    event TestTransactionExecuted(address indexed executor, uint256 value);

    function setUp() public {
        // Derive addresses from private keys
        eoaOwner = payable(vm.addr(EOA_PRIVATE_KEY));
        inheritor = payable(vm.addr(INHERITOR_PRIVATE_KEY));
        randomUser = payable(vm.addr(RANDOM_PRIVATE_KEY));
        
        // Deploy contracts
        inheritanceLogic = new EOAInheritanceLogic();
        eoaController = new EOAController();
        testTarget = new TestTarget();
        mockToken = new MockERC20("Test Token", "TEST", 18, 1000000 * 10**18);
        
        // Fund accounts
        vm.deal(eoaOwner, 10 ether);
        vm.deal(inheritor, 10 ether);
        vm.deal(randomUser, 10 ether);

        // Transfer some tokens to EOA for testing
        mockToken.transfer(eoaOwner, 10000 * 10**18);
        
        console.log("EOA Owner:", eoaOwner);
        console.log("Inheritor:", inheritor);
        console.log("InheritanceLogic:", address(inheritanceLogic));
    }

    // --- EIP-7702 Delegation Tests ---
    
    function test_EOA_SetupInheritanceWithDelegation() public {
        // Step 1: EOA delegates to inheritance logic using EIP-7702
        vm.signAndAttachDelegation(address(inheritanceLogic), EOA_PRIVATE_KEY);
        
        // Step 2: EOA calls setupInheritance (now executing inheritance logic)
        vm.prank(eoaOwner);
        EOAInheritanceLogic(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);
        
        // Step 3: Verify inheritance is set up correctly
        (address configInheritor, uint256 period, uint256 lastActive, uint256 gracePeriod) = 
            EOAInheritanceLogic(eoaOwner).getInheritanceConfig();
            
        assertEq(configInheritor, inheritor);
        assertEq(period, VALID_PERIOD);
        assertEq(lastActive, block.timestamp);
        assertEq(gracePeriod, GRACE_PERIOD);
        assertEq(EOAInheritanceLogic(eoaOwner).getAuthorizedOwner(), eoaOwner);
    }
    
    function test_EOA_KeepAliveWithDelegation() public {
        // Setup inheritance first
        vm.signAndAttachDelegation(address(inheritanceLogic), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAInheritanceLogic(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);
        
        // Fast forward time
        vm.warp(block.timestamp + 30 days);
        
        // EOA keeps alive
        vm.signAndAttachDelegation(address(inheritanceLogic), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAInheritanceLogic(eoaOwner).keepAlive();
        
        // Verify last active timestamp is updated
        (, , uint256 lastActive, ) = EOAInheritanceLogic(eoaOwner).getInheritanceConfig();
        assertEq(lastActive, block.timestamp);
    }

    function test_EOA_InheritorCanClaimOwnership() public {
        // Step 1: Setup inheritance
        vm.signAndAttachDelegation(address(inheritanceLogic), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAInheritanceLogic(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);
        
        // Step 2: Fast forward past inactivity + grace period
        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);
        
        // Step 3: Inheritor claims ownership
        vm.signAndAttachDelegation(address(inheritanceLogic), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAInheritanceLogic(eoaOwner).claimOwnership();
        
        // Step 4: Verify ownership transfer
        assertEq(EOAInheritanceLogic(eoaOwner).getAuthorizedOwner(), inheritor);
        
        // Step 5: Verify inheritance config is cleared
        (address configInheritor, uint256 period, , uint256 gracePeriod) = 
            EOAInheritanceLogic(eoaOwner).getInheritanceConfig();
        assertEq(configInheritor, address(0));
        assertEq(period, 0);
        assertEq(gracePeriod, 0);
    }

    function test_EOA_InheritorCanControlEOAAfterClaim() public {
        // Step 1: Setup inheritance
        vm.signAndAttachDelegation(address(inheritanceLogic), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAInheritanceLogic(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);
        
        // Step 2: Fast forward and claim ownership
        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);
        vm.signAndAttachDelegation(address(inheritanceLogic), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAInheritanceLogic(eoaOwner).claimOwnership();
        
        // Step 3: Inheritor can now control the EOA for transactions
        // Test 1: Inheritor can send ETH from EOA
        uint256 initialBalance = address(testTarget).balance;
        vm.prank(inheritor);
        (bool success, ) = payable(address(testTarget)).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(testTarget).balance, initialBalance + 1 ether);
        
        // Test 2: Inheritor can call contracts from EOA
        vm.prank(inheritor);
        testTarget.executeTransaction{value: 0.5 ether}(42);
        assertEq(testTarget.lastValue(), 42);
        assertEq(testTarget.lastExecutor(), inheritor); // Inheritor is the actual caller
        
        // Test 3: Inheritor can setup new inheritance from EOA
        address newInheritor = makeAddr("newInheritor");
        vm.signAndAttachDelegation(address(inheritanceLogic), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAInheritanceLogic(eoaOwner).setupInheritance(newInheritor, VALID_PERIOD);
        
        (address configInheritor, , , ) = EOAInheritanceLogic(eoaOwner).getInheritanceConfig();
        assertEq(configInheritor, newInheritor);
    }

    function test_EOA_OriginalOwnerCannotControlAfterClaim() public {
        // Setup and claim inheritance
        vm.signAndAttachDelegation(address(inheritanceLogic), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAInheritanceLogic(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);
        
        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);
        vm.signAndAttachDelegation(address(inheritanceLogic), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAInheritanceLogic(eoaOwner).claimOwnership();
        
        // Original owner cannot use inheritance functions anymore
        vm.signAndAttachDelegation(address(inheritanceLogic), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        vm.expectRevert(EOAInheritanceLogic.UnauthorizedAccess.selector);
        EOAInheritanceLogic(eoaOwner).setupInheritance(makeAddr("newInheritor"), VALID_PERIOD);
    }

    function test_EOA_InactivityPeriodNotMet() public {
        // Setup inheritance
        vm.signAndAttachDelegation(address(inheritanceLogic), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAInheritanceLogic(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);
        
        // Try to claim before period is met
        vm.warp(block.timestamp + VALID_PERIOD); // Only inactivity period, not grace period
        
        vm.signAndAttachDelegation(address(inheritanceLogic), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        vm.expectRevert(EOAInheritanceLogic.InactivityPeriodNotMet.selector);
        EOAInheritanceLogic(eoaOwner).claimOwnership();
    }

    function test_EOA_FullInheritanceFlowWithRealTransactions() public {
        // Step 1: EOA owner sets up inheritance
        vm.signAndAttachDelegation(address(inheritanceLogic), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAInheritanceLogic(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);
        
        // Step 2: EOA owner makes some transactions (proving activity)
        vm.prank(eoaOwner);
        testTarget.executeTransaction{value: 1 ether}(100);
        assertEq(testTarget.lastExecutor(), eoaOwner);
        
        // Step 3: EOA owner stays active for a while
        vm.warp(block.timestamp + 30 days);
        vm.signAndAttachDelegation(address(inheritanceLogic), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAInheritanceLogic(eoaOwner).keepAlive();
        
        // Step 4: EOA owner becomes inactive
        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);
        
        // Step 5: Inheritor claims ownership
        vm.signAndAttachDelegation(address(inheritanceLogic), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAInheritanceLogic(eoaOwner).claimOwnership();
        
        // Step 6: Inheritor can now control EOA and make transactions
        vm.prank(inheritor);
        testTarget.executeTransaction{value: 2 ether}(200);
        assertEq(testTarget.lastExecutor(), inheritor); // Inheritor is the actual caller
        assertEq(testTarget.lastValue(), 200);
        
        // Step 7: Inheritor sets up new inheritance
        address nextInheritor = makeAddr("nextInheritor");
        vm.signAndAttachDelegation(address(inheritanceLogic), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAInheritanceLogic(eoaOwner).setupInheritance(nextInheritor, VALID_PERIOD);
        
        // Verify the cycle can continue
        (address configInheritor, , , ) = EOAInheritanceLogic(eoaOwner).getInheritanceConfig();
        assertEq(configInheritor, nextInheritor);
        assertEq(EOAInheritanceLogic(eoaOwner).getAuthorizedOwner(), inheritor);
    }

    // --- EOAController Tests ---

    function test_EOA_InheritorCanExecuteTransactionsWithController() public {
        // Setup inheritance and claim ownership
        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAController(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);

        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).claimOwnership();

        // Test 1: Execute single transaction
        bytes memory data = abi.encodeWithSignature("executeTransaction(uint256)", 123);
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        (bool success, ) = EOAController(eoaOwner).executeTransaction(
            address(testTarget),
            0.1 ether,
            data
        );

        assertTrue(success);
        assertEq(testTarget.lastValue(), 123);
        assertEq(testTarget.lastExecutor(), eoaOwner); // EOA is the actual executor
    }

    function test_EOA_InheritorCanTransferETH() public {
        // Setup and claim ownership
        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAController(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);

        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).claimOwnership();

        // Transfer ETH from EOA
        address recipient = makeAddr("recipient");
        uint256 initialBalance = recipient.balance;

        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).transferETH(payable(recipient), 1 ether);

        assertEq(recipient.balance, initialBalance + 1 ether);
    }

    function test_EOA_InheritorCanExecuteBatchTransactions() public {
        // Setup and claim ownership
        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAController(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);

        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).claimOwnership();

        // Prepare batch transactions
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory dataArray = new bytes[](2);

        targets[0] = address(testTarget);
        values[0] = 0.1 ether;
        dataArray[0] = abi.encodeWithSignature("executeTransaction(uint256)", 111);

        targets[1] = address(testTarget);
        values[1] = 0.2 ether;
        dataArray[1] = abi.encodeWithSignature("executeTransaction(uint256)", 222);

        // Execute batch
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        uint256 successCount = EOAController(eoaOwner).executeBatchTransactions(
            targets,
            values,
            dataArray
        );

        assertEq(successCount, 2);
        assertEq(testTarget.lastValue(), 222); // Last transaction value
    }

    function test_EOA_CheckBalanceAndCanExecute() public {
        // Setup and claim ownership
        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAController(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);

        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).claimOwnership();

        // Check ETH balance
        uint256 balance = EOAController(eoaOwner).getETHBalance();
        assertEq(balance, 10 ether); // Initial funding

        // Check if can execute transaction
        (bool canExecute, string memory reason) = EOAController(eoaOwner).canExecuteTransaction(
            address(testTarget),
            1 ether
        );
        assertTrue(canExecute);
        assertEq(reason, "");

        // Check if cannot execute transaction with insufficient balance
        (bool canExecuteHigh, string memory reasonHigh) = EOAController(eoaOwner).canExecuteTransaction(
            address(testTarget),
            20 ether
        );
        assertFalse(canExecuteHigh);
        assertEq(reasonHigh, "Insufficient ETH balance");
    }

    function test_EOA_EmergencyWithdraw() public {
        // Setup and claim ownership
        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAController(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);

        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).claimOwnership();

        // Emergency withdraw all ETH
        address emergencyRecipient = makeAddr("emergency");
        uint256 initialBalance = emergencyRecipient.balance;
        uint256 eoaBalance = EOAController(eoaOwner).getETHBalance();

        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).emergencyWithdraw(payable(emergencyRecipient));

        assertEq(emergencyRecipient.balance, initialBalance + eoaBalance);
        assertEq(EOAController(eoaOwner).getETHBalance(), 0);
    }

    function test_EOA_UnauthorizedCannotUseController() public {
        // Setup inheritance but don't claim
        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAController(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);

        // Random user cannot execute transactions
        vm.signAndAttachDelegation(address(eoaController), RANDOM_PRIVATE_KEY);
        vm.prank(randomUser);
        vm.expectRevert(EOAInheritanceLogic.UnauthorizedAccess.selector);
        EOAController(eoaOwner).transferETH(payable(randomUser), 1 ether);
    }

    function test_EOA_InheritorCanTransferERC20() public {
        // Setup and claim ownership
        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAController(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);

        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).claimOwnership();

        // Check initial token balance
        uint256 initialBalance = EOAController(eoaOwner).getERC20Balance(address(mockToken));
        assertEq(initialBalance, 10000 * 10**18);

        // Transfer tokens from EOA
        address recipient = makeAddr("tokenRecipient");
        uint256 transferAmount = 1000 * 10**18;

        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).transferERC20(address(mockToken), recipient, transferAmount);

        // Verify transfer
        assertEq(mockToken.balanceOf(recipient), transferAmount);
        assertEq(mockToken.balanceOf(eoaOwner), initialBalance - transferAmount);
    }

    function test_EOA_InheritorCanApproveERC20() public {
        // Setup and claim ownership
        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAController(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);

        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).claimOwnership();

        // Approve token spending
        address spender = makeAddr("spender");
        uint256 approveAmount = 5000 * 10**18;

        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).approveERC20(address(mockToken), spender, approveAmount);

        // Verify approval
        assertEq(mockToken.allowance(eoaOwner, spender), approveAmount);
    }

    function test_EOA_CompleteInheritanceScenarioWithAssets() public {
        // This test simulates a complete inheritance scenario where:
        // 1. EOA owner has ETH and ERC20 tokens
        // 2. Sets up inheritance
        // 3. Becomes inactive
        // 4. Inheritor claims and manages all assets

        // Step 1: EOA owner sets up inheritance
        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAController(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);

        // Step 2: Verify initial assets
        uint256 initialETH = EOAController(eoaOwner).getETHBalance();
        uint256 initialTokens = EOAController(eoaOwner).getERC20Balance(address(mockToken));
        assertEq(initialETH, 10 ether);
        assertEq(initialTokens, 10000 * 10**18);

        // Step 3: EOA owner becomes inactive
        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);

        // Step 4: Inheritor claims ownership
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).claimOwnership();

        // Step 5: Inheritor manages ETH assets
        address ethRecipient = makeAddr("ethRecipient");
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).transferETH(payable(ethRecipient), 2 ether);
        assertEq(ethRecipient.balance, 2 ether);

        // Step 6: Inheritor manages token assets
        address tokenRecipient = makeAddr("tokenRecipient");
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).transferERC20(address(mockToken), tokenRecipient, 3000 * 10**18);
        assertEq(mockToken.balanceOf(tokenRecipient), 3000 * 10**18);

        // Step 7: Test additional ETH transfer via controller
        address additionalEthRecipient = makeAddr("additionalEthRecipient");
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).transferETH(payable(additionalEthRecipient), 1.5 ether);
        assertEq(additionalEthRecipient.balance, 1.5 ether);

        // Step 8: Test additional ERC20 transfer via controller
        address additionalTokenRecipient = makeAddr("additionalTokenRecipient");
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).transferERC20(address(mockToken), additionalTokenRecipient, 1500 * 10**18);
        assertEq(mockToken.balanceOf(additionalTokenRecipient), 1500 * 10**18);

        // Step 9: Test contract interaction via controller
        bytes memory data = abi.encodeWithSignature("executeTransaction(uint256)", 999);
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).executeTransaction(address(testTarget), 0.3 ether, data);
        assertEq(testTarget.lastValue(), 999);
        assertEq(testTarget.lastExecutor(), eoaOwner); // EOA is the caller via delegation

        // Step 10: Inheritor sets up new inheritance
        address nextInheritor = makeAddr("nextInheritor");
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).setupInheritance(nextInheritor, VALID_PERIOD);

        // Step 11: Verify the inheritance cycle continues
        (address configInheritor, , , ) = EOAController(eoaOwner).getInheritanceConfig();
        assertEq(configInheritor, nextInheritor);
        assertEq(EOAController(eoaOwner).getAuthorizedOwner(), inheritor);

        // Step 12: Verify remaining assets after all transfers
        // Total ETH transferred: 2 + 1.5 + 0.3 = 3.8 ether
        uint256 expectedEthBalance = 10 ether - 3.8 ether;
        assertEq(eoaOwner.balance, expectedEthBalance);

        // Total tokens transferred: 3000 + 1500 = 4500 * 10**18
        uint256 expectedTokenBalance = 10000 * 10**18 - 4500 * 10**18;
        assertEq(mockToken.balanceOf(eoaOwner), expectedTokenBalance);
    }

    function test_EOA_InheritorCanSendETHViaController() public {
        // Setup inheritance and claim ownership
        _setupAndClaimInheritance();

        uint256 initialBalance = eoaOwner.balance;
        address recipient1 = makeAddr("ethRecipient1");
        address recipient2 = makeAddr("ethRecipient2");

        // Inheritor sends ETH via EOAController (which is delegated by EOA)
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).transferETH(payable(recipient1), 2 ether);
        assertEq(recipient1.balance, 2 ether);

        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).transferETH(payable(recipient2), 1.5 ether);
        assertEq(recipient2.balance, 1.5 ether);

        // Verify EOA balance decreased
        assertEq(eoaOwner.balance, initialBalance - 3.5 ether);
    }

    function test_EOA_InheritorCanSendTokensViaController() public {
        // Setup inheritance and claim ownership
        _setupAndClaimInheritance();

        uint256 initialTokens = mockToken.balanceOf(eoaOwner);
        address recipient1 = makeAddr("tokenRecipient1");
        address recipient2 = makeAddr("tokenRecipient2");

        // Inheritor sends tokens via EOAController (which is delegated by EOA)
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).transferERC20(address(mockToken), recipient1, 2000 * 10**18);
        assertEq(mockToken.balanceOf(recipient1), 2000 * 10**18);

        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).transferERC20(address(mockToken), recipient2, 1500 * 10**18);
        assertEq(mockToken.balanceOf(recipient2), 1500 * 10**18);

        // Verify EOA token balance decreased
        assertEq(mockToken.balanceOf(eoaOwner), initialTokens - 3500 * 10**18);
    }

    function test_EOA_InheritorCanInteractWithContractsViaController() public {
        // Setup inheritance and claim ownership
        _setupAndClaimInheritance();

        uint256 initialTargetBalance = address(testTarget).balance;

        // Inheritor interacts with contract via EOAController
        bytes memory data = abi.encodeWithSignature("executeTransaction(uint256)", 12345);
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).executeTransaction(address(testTarget), 0.5 ether, data);

        assertEq(testTarget.lastValue(), 12345);
        assertEq(testTarget.lastExecutor(), eoaOwner); // EOA is the actual caller via delegation
        assertEq(address(testTarget).balance, initialTargetBalance + 0.5 ether);
    }

    function test_EOA_InheritorCanApproveTokensViaController() public {
        // Setup inheritance and claim ownership
        _setupAndClaimInheritance();

        address spender = makeAddr("spender");

        // Inheritor approves tokens via EOAController
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).approveERC20(address(mockToken), spender, 1000 * 10**18);
        assertEq(mockToken.allowance(eoaOwner, spender), 1000 * 10**18);

        // Spender can use the approved tokens
        vm.prank(spender);
        bool transferFromSuccess = mockToken.transferFrom(eoaOwner, spender, 1000 * 10**18);
        assertTrue(transferFromSuccess);
        assertEq(mockToken.balanceOf(spender), 1000 * 10**18);
    }

    // Helper function to reduce code duplication
    function _setupAndClaimInheritance() internal {
        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAController(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);

        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).claimOwnership();
    }

    function test_EOA_InheritorCannotUseControllerBeforeClaim() public {
        // Test that inheritor cannot use controller functions before claiming ownership

        // Step 1: Setup inheritance but don't claim yet
        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAController(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);

        // Step 2: Try to use controller before claiming (should fail)
        address recipient = makeAddr("recipient");

        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        vm.expectRevert(EOAInheritanceLogic.UnauthorizedAccess.selector);
        EOAController(eoaOwner).transferETH(payable(recipient), 1 ether);

        // Step 3: Try to transfer tokens before claiming (should fail)
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        vm.expectRevert(EOAInheritanceLogic.UnauthorizedAccess.selector);
        EOAController(eoaOwner).transferERC20(address(mockToken), recipient, 1000 * 10**18);
    }

    function test_EOA_OriginalOwnerCannotUseControllerAfterClaim() public {
        // Test that original owner cannot use controller functions after inheritance is claimed

        // Step 1: Setup inheritance and claim ownership
        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        EOAController(eoaOwner).setupInheritance(inheritor, VALID_PERIOD);

        vm.warp(block.timestamp + VALID_PERIOD + GRACE_PERIOD + 1);
        vm.signAndAttachDelegation(address(eoaController), INHERITOR_PRIVATE_KEY);
        vm.prank(inheritor);
        EOAController(eoaOwner).claimOwnership();

        // Step 2: Original owner tries to use controller (should fail)
        address recipient = makeAddr("recipient");

        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        vm.expectRevert(EOAInheritanceLogic.UnauthorizedAccess.selector);
        EOAController(eoaOwner).transferETH(payable(recipient), 1 ether);

        // Step 3: Original owner tries to transfer tokens via controller (should fail)
        vm.signAndAttachDelegation(address(eoaController), EOA_PRIVATE_KEY);
        vm.prank(eoaOwner);
        vm.expectRevert(EOAInheritanceLogic.UnauthorizedAccess.selector);
        EOAController(eoaOwner).transferERC20(address(mockToken), recipient, 1000 * 10**18);
    }
}

/**
 * @title TestTarget
 * @dev A simple contract for testing EOA interactions
 */
contract TestTarget {
    address public lastExecutor;
    uint256 public lastValue;
    
    event TestTransactionExecuted(address indexed executor, uint256 value);
    
    function executeTransaction(uint256 value) external payable {
        lastExecutor = msg.sender;
        lastValue = value;
        emit TestTransactionExecuted(msg.sender, value);
    }
    
    receive() external payable {}
}
