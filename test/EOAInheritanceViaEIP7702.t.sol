// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/InheritanceManager.sol";
import "../examples/EOAInheritanceViaEIP7702.sol";
import "./helpers/StateProofHelper.sol";

/**
 * @title EOAInheritanceViaEIP7702Test
 * @dev Tests demonstrating how inheritor gains control of actual EOA via EIP-7702
 */
contract EOAInheritanceViaEIP7702Test is Test {
    
    InheritanceManager public inheritanceManager;
    EIP7702InheritanceController public controller;
    MockERC20 public token;
    StateProofHelper public stateProofHelper;
    
    // Test accounts
    address public eoaAccount = address(0x1234567890123456789012345678901234567890);     // The EOA that will be inherited
    address public inheritor = address(0x2345678901234567890123456789012345678901);      // The inheritor
    address public recipient = address(0x3456789012345678901234567890123456789012);      // Recipient of transferred assets
    
    // Test parameters
    uint256 public constant INACTIVITY_PERIOD = 1_314_000; // ~6 months
    uint256 public constant TEST_BLOCK = 1000;
    
    function setUp() public {
        // Deploy contracts
        inheritanceManager = new InheritanceManager();
        controller = new EIP7702InheritanceController(address(inheritanceManager));
        token = new MockERC20("Test Token", "TEST");
        stateProofHelper = new StateProofHelper();
        
        // Fund the EOA account
        vm.deal(eoaAccount, 10 ether);
        token.mint(eoaAccount, 1000 * 10**18);
        
        // Fund other accounts
        vm.deal(inheritor, 1 ether);
        vm.deal(recipient, 1 ether);
        
        // Set current block number
        vm.roll(TEST_BLOCK);
    }
    
    function testCompleteEOAInheritanceFlow() public {
        // Step 1: Configure inheritance for the EOA
        vm.prank(eoaAccount);
        inheritanceManager.configureInheritance(eoaAccount, inheritor, INACTIVITY_PERIOD);
        
        // Step 2: Mark inactivity start
        vm.roll(TEST_BLOCK + 100);

        // Generate test block header and account state proof
        uint256 blockNumber = TEST_BLOCK + 100;
        bytes memory blockHeaderRLP = stateProofHelper.generateBlockHeaderRLP(blockNumber);

        // Mock blockhash to return the expected value for our test header
        bytes32 expectedBlockHash = keccak256(blockHeaderRLP);
        vm.mockCall(
            address(0), // blockhash is a global function
            abi.encodeWithSignature("blockhash(uint256)", blockNumber),
            abi.encode(expectedBlockHash)
        );

        InheritanceManager.AccountStateProof memory accountStateProof = InheritanceManager.AccountStateProof({
            nonce: 42,
            balance: 10 ether,
            storageHash: keccak256(abi.encodePacked("storage", eoaAccount)),
            codeHash: keccak256(abi.encodePacked("code", eoaAccount)),
            proof: stateProofHelper.generateAccountProof(eoaAccount, 42, 10 ether)
        });

        inheritanceManager.markInactivityStartWithProof(
            eoaAccount,
            blockHeaderRLP,
            accountStateProof
        );
        
        // Step 3: Wait for inactivity period
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1);
        
        // Step 4: Claim inheritance
        uint256 claimBlockNumber = TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1;
        bytes memory claimBlockHeaderRLP = stateProofHelper.generateBlockHeaderRLP(claimBlockNumber);

        InheritanceManager.AccountStateProof memory claimAccountStateProof = InheritanceManager.AccountStateProof({
            nonce: 42, // same nonce (inactive)
            balance: 10 ether, // same balance (inactive)
            storageHash: keccak256(abi.encodePacked("storage", eoaAccount)),
            codeHash: keccak256(abi.encodePacked("code", eoaAccount)),
            proof: stateProofHelper.generateAccountProof(eoaAccount, 42, 10 ether)
        });

        vm.prank(inheritor);
        inheritanceManager.claimInheritanceWithProof(
            eoaAccount,
            claimBlockHeaderRLP,
            claimAccountStateProof
        );
        
        // Verify inheritance is claimed
        assertTrue(inheritanceManager.isInheritanceClaimed(eoaAccount));
        
        // Step 5: Simulate EIP-7702 delegation
        // In a real scenario, the EOA would delegate to the controller via EIP-7702
        // For testing, we'll simulate this by setting the controller's address as the EOA
        
        // Deploy a new controller instance that thinks it's the EOA
        vm.etch(eoaAccount, address(controller).code);
        
        // Configure the controller to recognize the inheritance
        vm.store(
            eoaAccount,
            bytes32(uint256(0)), // inheritanceManager slot
            bytes32(uint256(uint160(address(inheritanceManager))))
        );
        
        // Step 6: Inheritor can now control the EOA directly
        EIP7702InheritanceController eoaController = EIP7702InheritanceController(payable(eoaAccount));
        
        // Test ETH transfer from EOA using execute()
        uint256 initialBalance = recipient.balance;
        vm.prank(inheritor);
        eoaController.execute(recipient, 1 ether, "");

        assertEq(recipient.balance, initialBalance + 1 ether);
        assertEq(eoaAccount.balance, 9 ether);

        // Test token transfer from EOA using execute()
        uint256 initialTokenBalance = token.balanceOf(recipient);
        bytes memory transferCall = abi.encodeWithSelector(
            token.transfer.selector,
            recipient,
            100 * 10**18
        );
        vm.prank(inheritor);
        eoaController.execute(address(token), 0, transferCall);

        assertEq(token.balanceOf(recipient), initialTokenBalance + 100 * 10**18);
        assertEq(token.balanceOf(eoaAccount), 900 * 10**18);
    }

    function testEOABalanceQueriesDirect() public {
        // Setup inheritance and claim it
        _setupAndClaimInheritance();

        // Simulate EIP-7702 delegation
        vm.etch(eoaAccount, address(controller).code);
        vm.store(
            eoaAccount,
            bytes32(uint256(0)),
            bytes32(uint256(uint160(address(inheritanceManager))))
        );

        // Test direct balance queries on the EOA address
        assertEq(eoaAccount.balance, 10 ether, "EOA ETH balance should be queryable directly");
        assertEq(token.balanceOf(eoaAccount), 1000 * 10**18, "EOA token balance should be queryable directly");

        // Record initial recipient balance
        uint256 initialRecipientETH = recipient.balance;
        uint256 initialRecipientTokens = token.balanceOf(recipient);

        // After transactions, balances should update
        EIP7702InheritanceController eoaController = EIP7702InheritanceController(payable(eoaAccount));

        vm.prank(inheritor);
        eoaController.execute(recipient, 2 ether, "");

        bytes memory tokenTransferCall = abi.encodeWithSelector(
            token.transfer.selector,
            recipient,
            300 * 10**18
        );

        vm.prank(inheritor);
        eoaController.execute(address(token), 0, tokenTransferCall);

        // Verify updated balances are queryable directly
        assertEq(eoaAccount.balance, 8 ether, "EOA ETH balance should update after transfer");
        assertEq(token.balanceOf(eoaAccount), 700 * 10**18, "EOA token balance should update after transfer");
        assertEq(recipient.balance, initialRecipientETH + 2 ether, "Recipient should receive additional ETH");
        assertEq(token.balanceOf(recipient), initialRecipientTokens + 300 * 10**18, "Recipient should receive additional tokens");
    }

    function testEOAExecuteFunction() public {
        // Setup inheritance and claim it
        _setupAndClaimInheritance();
        
        // Simulate EIP-7702 delegation
        vm.etch(eoaAccount, address(controller).code);
        vm.store(
            eoaAccount,
            bytes32(uint256(0)),
            bytes32(uint256(uint160(address(inheritanceManager))))
        );
        
        EIP7702InheritanceController eoaController = EIP7702InheritanceController(payable(eoaAccount));
        
        // Test arbitrary contract execution from EOA
        TestTarget target = new TestTarget();
        
        bytes memory callData = abi.encodeWithSelector(TestTarget.setValue.selector, 42);
        
        vm.prank(inheritor);
        eoaController.execute(address(target), 0, callData);
        
        assertEq(target.value(), 42);
    }
    
    function testEOABatchExecution() public {
        // Setup inheritance and claim it
        _setupAndClaimInheritance();
        
        // Simulate EIP-7702 delegation
        vm.etch(eoaAccount, address(controller).code);
        vm.store(
            eoaAccount,
            bytes32(uint256(0)),
            bytes32(uint256(uint160(address(inheritanceManager))))
        );
        
        EIP7702InheritanceController eoaController = EIP7702InheritanceController(payable(eoaAccount));
        
        // Prepare batch transactions
        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);
        
        targets[0] = recipient;
        values[0] = 1 ether;
        data[0] = "";
        
        targets[1] = address(token);
        values[1] = 0;
        data[1] = abi.encodeWithSelector(token.transfer.selector, recipient, 50 * 10**18);
        
        // Execute batch from EOA
        vm.prank(inheritor);
        eoaController.executeBatch(targets, values, data);
        
        // Verify results
        assertEq(recipient.balance, 2 ether); // 1 ether initial + 1 ether transferred
        assertEq(token.balanceOf(recipient), 50 * 10**18);
    }
    
    function testUnauthorizedAccess() public {
        // Setup inheritance but don't claim it
        vm.prank(eoaAccount);
        inheritanceManager.configureInheritance(eoaAccount, inheritor, INACTIVITY_PERIOD);
        
        // Simulate EIP-7702 delegation
        vm.etch(eoaAccount, address(controller).code);
        vm.store(
            eoaAccount,
            bytes32(uint256(0)),
            bytes32(uint256(uint160(address(inheritanceManager))))
        );
        
        EIP7702InheritanceController eoaController = EIP7702InheritanceController(payable(eoaAccount));
        
        // Try to transfer without claiming inheritance
        vm.prank(inheritor);
        vm.expectRevert("Inheritance not claimed");
        eoaController.execute(recipient, 1 ether, "");
    }
    
    function testNonInheritorAccess() public {
        // Setup and claim inheritance
        _setupAndClaimInheritance();
        
        // Simulate EIP-7702 delegation
        vm.etch(eoaAccount, address(controller).code);
        vm.store(
            eoaAccount,
            bytes32(uint256(0)),
            bytes32(uint256(uint160(address(inheritanceManager))))
        );
        
        EIP7702InheritanceController eoaController = EIP7702InheritanceController(payable(eoaAccount));
        
        // Try to transfer as non-inheritor
        vm.prank(recipient);
        vm.expectRevert("Not the inheritor");
        eoaController.execute(recipient, 1 ether, "");
    }
    

    
    // Helper function to setup and claim inheritance
    function _setupAndClaimInheritance() internal {
        // Configure inheritance
        vm.prank(eoaAccount);
        inheritanceManager.configureInheritance(eoaAccount, inheritor, INACTIVITY_PERIOD);

        // Mark inactivity
        vm.roll(TEST_BLOCK + 100);
        uint256 blockNumber = TEST_BLOCK + 100;
        bytes memory blockHeaderRLP = stateProofHelper.generateBlockHeaderRLP(blockNumber);

        InheritanceManager.AccountStateProof memory accountStateProof = InheritanceManager.AccountStateProof({
            nonce: 42,
            balance: 10 ether,
            storageHash: keccak256(abi.encodePacked("storage", eoaAccount)),
            codeHash: keccak256(abi.encodePacked("code", eoaAccount)),
            proof: stateProofHelper.generateAccountProof(eoaAccount, 42, 10 ether)
        });

        inheritanceManager.markInactivityStartWithProof(eoaAccount, blockHeaderRLP, accountStateProof);

        // Wait and claim
        vm.roll(TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1);
        uint256 claimBlockNumber = TEST_BLOCK + 100 + INACTIVITY_PERIOD + 1;
        bytes memory claimBlockHeaderRLP = stateProofHelper.generateBlockHeaderRLP(claimBlockNumber);

        InheritanceManager.AccountStateProof memory claimAccountStateProof = InheritanceManager.AccountStateProof({
            nonce: 42, // same nonce (inactive)
            balance: 10 ether, // same balance (inactive)
            storageHash: keccak256(abi.encodePacked("storage", eoaAccount)),
            codeHash: keccak256(abi.encodePacked("code", eoaAccount)),
            proof: stateProofHelper.generateAccountProof(eoaAccount, 42, 10 ether)
        });

        vm.prank(inheritor);
        inheritanceManager.claimInheritanceWithProof(eoaAccount, claimBlockHeaderRLP, claimAccountStateProof);
    }
}

// Mock contracts for testing
contract MockERC20 {
    string public name;
    string public symbol;
    mapping(address => uint256) public balanceOf;
    
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }
    
    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract TestTarget {
    uint256 public value;
    
    function setValue(uint256 _value) external {
        value = _value;
    }
}
