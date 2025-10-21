Created draft for report:
https://github.com/klausnat/liquid-staking-audit-report/blob/main/LiquidStaking_Audit_Report.md

1. installed foundry kup and kontrol

2. went through tutorial (https://docs.runtimeverification.com/kontrol/guides/kontrol-example/k-control-flow-graph-kcfg)

   I noticed one little issue in tutorial, please check file 
   https://github.com/klausnat/liquid-staking-audit-report/blob/main/screenshots/test_title.jpg
   
   the same test has different names (I got an error when tried to copy-paste command from tutorial)
   
   In the suggested initial code, test title  differs from test title in suggested command in K Control Flow Graph (KCFG) tab.
   Later though, in `Proof Management` tab, this test was renamed (in Counter.t.sol code)
   
3. created tests to check LiquidStaking contract. 
https://github.com/klausnat/liquid-staking-audit-report/blob/main/test/LiquidStaking.t.sol

Initially just regular Foundry tests (more fuzzing tests will add later). Found issues, check screenshot:
https://github.com/klausnat/liquid-staking-audit-report/blob/main/screenshots/foundry_tests_failed.png

Used AI (included fuzzing tests).

received panic in tests with arithmetic underflow or overflow, and in general, in contract next issues were detected

- the contract mixes sETH balances with ETH withdrawals
- balance checks should be added: verification that users have enough sETH for withdrawals
- need to fix exit fee calculation: exit fees are calculated on sETH but subtracted from ETH
- heap removal logic: increment issues in the removeExpired function

Example: in function requestWithdraw we could add:

function requestWithdraw(uint256 amountETH, uint256 deadline) external {
        require(amountETH > 0, "Amount to be withdrawn should be positive");
        
        // Convert ETH amount to sETH and check balance
        uint256 sETHAmount = (amountETH * exchangeRate) / 1e18;
        require(sETHBalance[msg.sender] >= sETHAmount, "Insufficient sETH balance");
        
        // Deduct sETH balance immediately
        sETHBalance[msg.sender] -= sETHAmount;
        
        minHeap.push(Withdrawal(msg.sender, amountETH, deadline));
        _heapifyUp(minHeap.length - 1);
        emit WithdrawRequested(msg.sender, amountETH, deadline);
    }

4. We have a lot of issues to be fixed, so plan for the further work is the next:
   4.1. work with successfull tests: each successfull test should be also checked with fuzzing tests and kontrol (we know that symbolic executin covers more cases, so formal verification required on top of foundry tests)
   4.2. work with failed tests: suggest changes in source code, list problems for each failing function, implement changes and test with kontrol - do formal verification.
   4.3. Create report (README: https://github.com/klausnat/liquid-staking-audit-report/tree/main) 
        with a table of contents and a list of all tests performed, errors found, and suggestions... with appendix where all results are printed. like the one we would provide for the code audit
   