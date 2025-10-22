// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Only tests which PASS Foundry are listed here. 
// Kontrol found bug (security vulnerability) in these tests
// for test_UpdateExchangeRage_RevertIfNotOwner - Kontrol found that the contract could revert for different reasons.

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

    function test_Initialization() public view {
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
}
