// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {LiquidStaking} from "../src/LiquidStaking.sol";

contract LiquidStakingScript is Script {
    LiquidStaking public liquidstaking;

    function run() public {
        // Define constructor parameters
        uint256 initialExchangeRate = 1e18; // 1:1 exchange rate (adjust as needed)
        bool initialExitFeeEnabled = false; // Start with exit fee disabled
        
        vm.startBroadcast();
        
        // Pass the required parameters to the constructor
        liquidstaking = new LiquidStaking(initialExchangeRate, initialExitFeeEnabled);
        
        vm.stopBroadcast();
    }
}
