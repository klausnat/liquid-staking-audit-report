// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/LiquidStaking.sol";

contract LiquidStakingTest is Test {
    LiquidStaking public staking;
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    
    uint256 constant INITIAL_EXCHANGE_RATE = 1e18; // 1:1 rate
    uint256 constant STAKE_AMOUNT = 1 ether;
    
    function setUp() public {
        vm.prank(owner);
        staking = new LiquidStaking(INITIAL_EXCHANGE_RATE, true);
        
        // Fund users
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);
    }

    // ============ CONSTRUCTOR & OWNER TESTS ============

    function test_Initialization() public view{
        assertEq(staking.owner(), owner);
        assertEq(staking.exchangeRate(), INITIAL_EXCHANGE_RATE);
        assertTrue(staking.exitFeeEnabled());
        assertEq(staking.totalStaked(), 0);
    }

    function test_UpdateExchangeRate() public {
        vm.prank(owner);
        staking.updateExchangeRate(2e18);
        
        assertEq(staking.exchangeRate(), 2e18);
    }

    function test_UpdateExchangeRate_RevertIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert("Not the contract owner");
        staking.updateExchangeRate(2e18);
    }

    function test_UpdateExchangeRate_RevertIfZero() public {
        vm.prank(owner);
        vm.expectRevert("Exchange rate must be greater than zero");
        staking.updateExchangeRate(0);
    }

    function test_UpdateExitFee() public {
        vm.prank(owner);
        staking.updateExitFee(false);
        
        assertFalse(staking.exitFeeEnabled());
    }

    // ============ STAKING TESTS ============

    function test_Stake() public {
        vm.prank(user1);
        staking.stake{value: STAKE_AMOUNT}();
        
        assertEq(staking.sETHBalance(user1), STAKE_AMOUNT * INITIAL_EXCHANGE_RATE);
        assertEq(staking.totalStaked(), STAKE_AMOUNT);
        assertTrue(staking.stakeTimestamps(user1) > 0);
    }

    function test_Stake_RevertIfZero() public {
        vm.prank(user1);
        vm.expectRevert("Supplied ETH must be positive");
        staking.stake{value: 0}();
    }

    function test_Stake_WithDifferentExchangeRate() public {
        // Update exchange rate first
        vm.prank(owner);
        staking.updateExchangeRate(2e18);
        
        vm.prank(user1);
        staking.stake{value: STAKE_AMOUNT}();
        
        assertEq(staking.sETHBalance(user1), STAKE_AMOUNT * 2e18);
    }

    // ============ WITHDRAWAL REQUEST TESTS ============

    function test_RequestWithdraw() public {
        // First stake
        vm.prank(user1);
        staking.stake{value: STAKE_AMOUNT}();
        
        // Then request withdrawal
        uint256 withdrawAmount = 0.5 ether;
        uint256 deadline = block.timestamp + 1 days;
        
        vm.prank(user1);
        staking.requestWithdraw(withdrawAmount, deadline);
        
        // Check heap
        assertEq(staking.withdrawalHeapLength(), 1);
        
        (address requestUser, uint256 amount, uint256 requestDeadline) = staking.withdrawalHeapEntry(0);
        assertEq(requestUser, user1);
        assertEq(amount, withdrawAmount);
        assertEq(requestDeadline, deadline);
    }

    function test_RequestWithdraw_RevertIfZero() public {
        vm.prank(user1);
        vm.expectRevert("Amount to be withdrawn should be positive");
        staking.requestWithdraw(0, block.timestamp + 1 days);
    }

    function test_MultipleWithdrawalRequests() public {
        // Setup multiple users staking
        vm.prank(user1);
        staking.stake{value: 2 ether}();
        
        vm.prank(user2);
        staking.stake{value: 1 ether}();
        
        // Request withdrawals in different order
        vm.prank(user1);
        staking.requestWithdraw(1 ether, block.timestamp + 2 days); // Larger amount
        
        vm.prank(user2);
        staking.requestWithdraw(0.5 ether, block.timestamp + 1 days); // Smaller amount
        
        // Min-heap should order smallest first
        (, uint256 smallestAmount, ) = staking.withdrawalHeapEntry(0);
        assertEq(smallestAmount, 0.5 ether); // user2's request should be first
    }

    // ============ WITHDRAWAL PROCESSING TESTS ============

    function test_ProcessWithdrawals() public {
        // Setup
        vm.prank(user1);
        staking.stake{value: 1 ether}();
        
        uint256 withdrawAmount = 0.5 ether;
        vm.prank(user1);
        staking.requestWithdraw(withdrawAmount, block.timestamp + 1 days);
        
        uint256 initialBalance = user1.balance;
        uint256 contractBalance = address(staking).balance;
        
        // Process withdrawal
        staking.processWithdrawals();
        
        // Check balances
        uint256 exitFee = staking.computeExitFee(user1);
        uint256 expectedReceived = withdrawAmount - exitFee;
        
        assertEq(user1.balance, initialBalance + expectedReceived);
        assertEq(address(staking).balance, contractBalance - withdrawAmount);
        assertEq(staking.totalStaked(), 0.5 ether); // Remaining stake
        assertEq(staking.withdrawalHeapLength(), 0);
    }

    function test_ProcessWithdrawals_RevertIfEmpty() public {
        vm.expectRevert("No withdrawals pending");
        staking.processWithdrawals();
    }

    function test_ProcessWithdrawals_NoExitFeeWhenDisabled() public {
        // Disable exit fee
        vm.prank(owner);
        staking.updateExitFee(false);
        
        // Setup stake and withdrawal
        vm.prank(user1);
        staking.stake{value: 1 ether}();
        
        uint256 withdrawAmount = 0.5 ether;
        vm.prank(user1);
        staking.requestWithdraw(withdrawAmount, block.timestamp + 1 days);
        
        uint256 initialBalance = user1.balance;
        
        // Process - should receive full amount without exit fee
        staking.processWithdrawals();
        
        assertEq(user1.balance, initialBalance + withdrawAmount);
    }

    // ============ EXIT FEE TESTS ============

    function test_ComputeExitFee() public {
        vm.prank(user1);
        staking.stake{value: 1 ether}();
        
        uint256 exitFee = staking.computeExitFee(user1);
        assertTrue(exitFee > 0);
        
        // Test after time passes
        vm.warp(block.timestamp + 1 days);
        uint256 exitFeeAfterTime = staking.computeExitFee(user1);
        assertTrue(exitFeeAfterTime < exitFee); // Fee should decrease over time
    }

    function test_ComputeExitFee_RevertIfNoStake() public {
        vm.expectRevert("User has no stake");
        staking.computeExitFee(user1);
    }

    // ============ EXPIRED REQUESTS TESTS ============

    function test_RemoveExpired() public {
        // Setup stake and expired request
        vm.prank(user1);
        staking.stake{value: 1 ether}();
        
        uint256 pastDeadline = block.timestamp - 1 hours;
        vm.prank(user1);
        staking.requestWithdraw(0.5 ether, pastDeadline);
        
        assertEq(staking.withdrawalHeapLength(), 1);
        
        // Remove expired
        staking.removeExpired();
        
        assertEq(staking.withdrawalHeapLength(), 0);
    }

    function test_RemoveExpired_MixedRequests() public {
        // Setup multiple requests
        vm.prank(user1);
        staking.stake{value: 2 ether}();
        
        vm.prank(user2);
        staking.stake{value: 1 ether}();
        
        // One expired, one valid
        vm.prank(user1);
        staking.requestWithdraw(1 ether, block.timestamp - 1 hours); // Expired
        
        vm.prank(user2);
        staking.requestWithdraw(0.5 ether, block.timestamp + 1 days); // Valid
        
        assertEq(staking.withdrawalHeapLength(), 2);
        
        // Remove expired - only user1's request should be removed
        staking.removeExpired();
        
        assertEq(staking.withdrawalHeapLength(), 1);
        
        // Check remaining request belongs to user2
        (address remainingUser, , ) = staking.withdrawalHeapEntry(0);
        assertEq(remainingUser, user2);
    }

    // ============ BULK UPDATE TESTS ============

    function test_BulkOwnerUpdateWithdrawals() public {
        // Setup
        vm.prank(user1);
        staking.stake{value: 1 ether}();
        
        vm.prank(user1);
        staking.requestWithdraw(0.5 ether, block.timestamp + 1 days);
        
        // Prepare update
        LiquidStaking.Withdrawal[] memory updates = new LiquidStaking.Withdrawal[](1);
        updates[0] = LiquidStaking.Withdrawal({
            user: user1,
            amountETH: 0.3 ether, // Updated amount
            deadline: block.timestamp + 2 days // Updated deadline
        });
        
        vm.prank(owner);
        staking.bulkOwnerUpdateWithdrawals(updates);
        
        // Verify update
        (, uint256 updatedAmount, uint256 updatedDeadline) = staking.withdrawalHeapEntry(0);
        assertEq(updatedAmount, 0.3 ether);
        assertEq(updatedDeadline, block.timestamp + 2 days);
    }

    function test_BulkOwnerUpdate_RevertIfNotOwner() public {
        LiquidStaking.Withdrawal[] memory updates = new LiquidStaking.Withdrawal[](0);
        
        vm.prank(user1);
        vm.expectRevert("Not the contract owner");
        staking.bulkOwnerUpdateWithdrawals(updates);
    }

    // ============ HEAP OPERATION TESTS ============

    function test_HeapOrdering() public {
        // Setup multiple stakes
        vm.prank(user1);
        staking.stake{value: 3 ether}();
        
        vm.prank(user2);
        staking.stake{value: 3 ether}();
        
        // Request withdrawals in random order
        vm.prank(user1);
        staking.requestWithdraw(2 ether, block.timestamp + 1 days); // Medium
        
        vm.prank(user2);
        staking.requestWithdraw(1 ether, block.timestamp + 1 days); // Smallest
        
        vm.prank(user1);
        staking.requestWithdraw(3 ether, block.timestamp + 1 days); // Largest
        
        // Verify min-heap ordering (smallest at root)
        (, uint256 smallest, ) = staking.withdrawalHeapEntry(0);
        assertEq(smallest, 1 ether); // user2's request
        
        // Process should take smallest first
        uint256 initialBalance = user2.balance;
        staking.processWithdrawals();
        
        // user2 should receive their withdrawal first
        assertTrue(user2.balance > initialBalance);
    }

    // ============ EDGE CASE TESTS ============

    function test_ReentrancyProtection() public {
        // This test would normally use a malicious contract, but here we test basic functionality
        vm.prank(user1);
        staking.stake{value: 1 ether}();
        
        vm.prank(user1);
        staking.requestWithdraw(0.5 ether, block.timestamp + 1 days);
        
        // Process multiple times to ensure state consistency
        staking.processWithdrawals();
        
        // Try to process again - should revert
        vm.expectRevert("No withdrawals pending");
        staking.processWithdrawals();
    }

    function test_WithdrawMoreThanStaked() public {
        vm.prank(user1);
        staking.stake{value: 1 ether}();
        
        // This should work since we're just creating a request
        vm.prank(user1);
        staking.requestWithdraw(2 ether, block.timestamp + 1 days);
        
        // But processing should handle the balance check internally
        // (Note: The current contract doesn't check if user has enough sETH for withdrawal)
        assertEq(staking.withdrawalHeapLength(), 1);
    }
}