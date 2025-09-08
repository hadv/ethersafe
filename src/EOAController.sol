// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./EOAInheritanceLogic.sol";

/**
 * @title EOAController
 * @dev Extended logic for EOA control after inheritance claim
 * This contract provides additional functionality for the inheritor
 * to control the EOA beyond just inheritance management
 */
contract EOAController is EOAInheritanceLogic {
    
    // Events
    event TransactionExecuted(address indexed target, uint256 value, bytes data, bool success);
    event BatchTransactionExecuted(uint256 indexed batchId, uint256 successCount, uint256 totalCount);
    
    // Custom errors
    error TransactionFailed();
    error InsufficientBalance();
    error InvalidTarget();

    /**
     * @notice Execute a transaction from the EOA
     * @dev Only the authorized owner can execute transactions
     * @param target The target contract address
     * @param value The ETH value to send
     * @param data The transaction data
     * @return success Whether the transaction succeeded
     * @return returnData The return data from the transaction
     */
    function executeTransaction(
        address target,
        uint256 value,
        bytes calldata data
    ) external onlyAuthorizedOwner nonReentrant returns (bool success, bytes memory returnData) {
        if (target == address(0)) revert InvalidTarget();
        if (address(this).balance < value) revert InsufficientBalance();
        
        (success, returnData) = target.call{value: value}(data);
        
        emit TransactionExecuted(target, value, data, success);
        
        if (!success) revert TransactionFailed();
    }

    /**
     * @notice Execute multiple transactions in a batch
     * @dev Only the authorized owner can execute batch transactions
     * @param targets Array of target addresses
     * @param values Array of ETH values to send
     * @param dataArray Array of transaction data
     * @return successCount Number of successful transactions
     */
    function executeBatchTransactions(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata dataArray
    ) external onlyAuthorizedOwner nonReentrant returns (uint256 successCount) {
        require(
            targets.length == values.length && values.length == dataArray.length,
            "Array length mismatch"
        );
        
        uint256 batchId = block.timestamp;
        successCount = 0;
        
        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] == address(0)) continue;
            if (address(this).balance < values[i]) continue;
            
            (bool success, ) = targets[i].call{value: values[i]}(dataArray[i]);
            
            emit TransactionExecuted(targets[i], values[i], dataArray[i], success);
            
            if (success) {
                successCount++;
            }
        }
        
        emit BatchTransactionExecuted(batchId, successCount, targets.length);
    }

    /**
     * @notice Transfer ETH from the EOA
     * @dev Only the authorized owner can transfer ETH
     * @param to The recipient address
     * @param amount The amount to transfer
     */
    function transferETH(address payable to, uint256 amount) 
        external 
        onlyAuthorizedOwner 
        nonReentrant 
    {
        if (to == address(0)) revert InvalidTarget();
        if (address(this).balance < amount) revert InsufficientBalance();
        
        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransactionFailed();
        
        emit TransactionExecuted(to, amount, "", success);
    }

    /**
     * @notice Transfer ERC20 tokens from the EOA
     * @dev Only the authorized owner can transfer tokens
     * @param token The token contract address
     * @param to The recipient address
     * @param amount The amount to transfer
     */
    function transferERC20(address token, address to, uint256 amount) 
        external 
        onlyAuthorizedOwner 
        nonReentrant 
    {
        if (token == address(0) || to == address(0)) revert InvalidTarget();
        
        // ERC20 transfer function signature: transfer(address,uint256)
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", to, amount);
        
        (bool success, bytes memory returnData) = token.call(data);
        
        // Check if the call was successful and returned true (for ERC20 compliance)
        bool transferSuccess = success && (returnData.length == 0 || abi.decode(returnData, (bool)));
        
        if (!transferSuccess) revert TransactionFailed();
        
        emit TransactionExecuted(token, 0, data, transferSuccess);
    }

    /**
     * @notice Approve ERC20 token spending from the EOA
     * @dev Only the authorized owner can approve token spending
     * @param token The token contract address
     * @param spender The spender address
     * @param amount The amount to approve
     */
    function approveERC20(address token, address spender, uint256 amount) 
        external 
        onlyAuthorizedOwner 
        nonReentrant 
    {
        if (token == address(0) || spender == address(0)) revert InvalidTarget();
        
        // ERC20 approve function signature: approve(address,uint256)
        bytes memory data = abi.encodeWithSignature("approve(address,uint256)", spender, amount);
        
        (bool success, bytes memory returnData) = token.call(data);
        
        // Check if the call was successful and returned true (for ERC20 compliance)
        bool approveSuccess = success && (returnData.length == 0 || abi.decode(returnData, (bool)));
        
        if (!approveSuccess) revert TransactionFailed();
        
        emit TransactionExecuted(token, 0, data, approveSuccess);
    }

    /**
     * @notice Get the ETH balance of the EOA
     * @return The current ETH balance
     */
    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @notice Get the ERC20 token balance of the EOA
     * @param token The token contract address
     * @return The current token balance
     */
    function getERC20Balance(address token) external view returns (uint256) {
        if (token == address(0)) return 0;
        
        // ERC20 balanceOf function signature: balanceOf(address)
        bytes memory data = abi.encodeWithSignature("balanceOf(address)", address(this));
        
        (bool success, bytes memory returnData) = token.staticcall(data);
        
        if (success && returnData.length >= 32) {
            return abi.decode(returnData, (uint256));
        }
        
        return 0;
    }

    /**
     * @notice Emergency withdrawal function
     * @dev Allows the authorized owner to withdraw all ETH in emergency situations
     * @param to The recipient address for the withdrawal
     */
    function emergencyWithdraw(address payable to) 
        external 
        onlyAuthorizedOwner 
        nonReentrant 
    {
        if (to == address(0)) revert InvalidTarget();
        
        uint256 balance = address(this).balance;
        if (balance == 0) return;
        
        (bool success, ) = to.call{value: balance}("");
        if (!success) revert TransactionFailed();
        
        emit TransactionExecuted(to, balance, "", success);
    }

    /**
     * @notice Check if the EOA can execute a transaction
     * @param target The target contract address
     * @param value The ETH value to send
     * @return canExecute Whether the transaction can be executed
     * @return reason The reason if transaction cannot be executed
     */
    function canExecuteTransaction(address target, uint256 value) 
        external 
        view 
        returns (bool canExecute, string memory reason) 
    {
        if (target == address(0)) {
            return (false, "Invalid target address");
        }
        
        if (address(this).balance < value) {
            return (false, "Insufficient ETH balance");
        }
        
        address currentOwner = _getAuthorizedOwner();
        if (currentOwner == address(0)) {
            return (false, "No authorized owner");
        }
        
        return (true, "");
    }

    // Allow the EOA to receive ETH
    receive() external payable {}
    
    // Fallback function for any other calls
    fallback() external payable {}
}
