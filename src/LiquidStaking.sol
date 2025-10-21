// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract LiquidStaking {
    // Owner of the contract authorized to adjust sensitive parameters
    address public owner;
    // Exchange rate between ETH and sETH
    uint256 public exchangeRate;
    // Total amount of ETH staked in the contract
    uint256 public totalStaked;
    // Flag indicating whether an exit fee is applied on withdrawal
    bool public exitFeeEnabled;

    /* Structure for withdrawal requests, tracking
     - user who submitted the request
     - amount to be withdrawn
     - deadline for the withdrawal — after expiration, the request should be removed
    */
    struct Withdrawal {
        address user;
        uint256 amountETH;
        uint256 deadline;
    }

    // Min-Heap data structure for withdrawal requests ordered by the amount of ETH to be withdrawn
    Withdrawal[] public minHeap;

    // Mapping of user addresses to their sETH balance
    mapping(address => uint256) public sETHBalance;

    // Mapping of user addresses to their staking timestamps
    mapping(address => uint256) public stakeTimestamps;

    // ─────────────────────────────────────────────────────
    // EVENTS
    // ─────────────────────────────────────────────────────

    event Staked(address indexed user, uint256 amountETH, uint256 amountSETH);
    event WithdrawRequested(address indexed user, uint256 amountETH, uint256 deadline);
    event WithdrawalProcessed(address indexed user, uint256 amountETH);
    event ExchangeRateUpdated(uint256 newRate);
    event WithdrawalRemoved(address indexed user);
    event ExitFeeToggled(bool enabled);
    event BulkUpdateCompleted(uint256 count);
    
    // ─────────────────────────────────────────────────────
    // FUNCTIONS
    // ─────────────────────────────────────────────────────

    /// @dev Sets the initial exchange rate, enables or disables exit fee, and assigns contract ownership
    /*
      Constructor is executed once during contract creation/deployment, e.g., via the
      LiquidStaking staking = new LiquidStaking(_initialExchangeRate, _initialExitFeeEnabled);
    */
    constructor(uint256 initialExchangeRate, bool initialExitFeeEnabled) {
        // No check on exchange rate, can be set to zero
        exchangeRate = initialExchangeRate;
        exitFeeEnabled = initialExitFeeEnabled;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    // @dev Returns the Withdrawal request at the specified index in the heap
    function withdrawalHeapEntry(uint256 i) external view returns (address, uint256, uint256) {
        Withdrawal memory w = minHeap[i];
        return (w.user, w.amountETH, w.deadline);
    }

    // @dev Returns the number of withdrawal requests in the heap
    function withdrawalHeapLength() external view returns (uint256) {
        return minHeap.length;
    }

    /// @dev Update the exchange rate, can only be called by an owner
    function updateExchangeRate(uint256 newRate) external onlyOwner {
        require(newRate > 0, "Exchange rate must be greater than zero");
        exchangeRate = newRate;
        emit ExchangeRateUpdated(newRate);
    }

    /// @dev Enables or disables the exit fee, can only be called by an owner
    function updateExitFee(bool enabled) external onlyOwner {
        exitFeeEnabled = enabled;
        emit ExitFeeToggled(enabled);
    }

    /// @dev Stake ETH and receive sETH tokens
    function stake() external payable {
        /*
        `msg.value` represent the amount of ETH sent with the transaction.
        The value must be greater than zero, otherwise the transaction will revert.
        To supply `amount` of ETH with a function call, the transaction must be sent with `value: amount`, e.g.
        `staking.stake{value: amount}()`.
        */
        require(msg.value > 0, "Supplied ETH must be positive");
        // Calculate the amount of sETH tokens to mint to the user
        uint256 sETHAmount = msg.value * exchangeRate;
        // Mint sETH
        sETHBalance[msg.sender] += sETHAmount;
        // Record the staked ETH
        totalStaked += msg.value;

        // Record the staking timestamp
        /*
         `block.timestamp` is the time of the current block 
          In Kontrol, by default, `block.timestamp` (and some other similar globally accessible variables) has a symbolic value
        */
        stakeTimestamps[msg.sender] = block.timestamp;

        emit Staked(msg.sender, msg.value, sETHAmount);
    }

    /// @dev Submit a request to withdraw the specified amount of ETH
    function requestWithdraw(uint256 amountETH, uint256 deadline) external {
        require(amountETH > 0, "Amount to be withdrawn should be positive");
        // Add the new request to the heap
        minHeap.push(Withdrawal(msg.sender, amountETH, deadline));
        // Bubble it up to maintain min-heap property
        _heapifyUp(minHeap.length - 1);

        emit WithdrawRequested(msg.sender, amountETH, deadline);
    }

    /// @dev Process a single withdrawal request in smallest-first order
    function processWithdrawals() external {
        require(minHeap.length > 0, "No withdrawals pending");
        // The smallest element is at index 0
        Withdrawal memory smallest = minHeap[0];

        // Calculate exit fee if applicable
        uint256 exitFee = exitFeeEnabled ? computeExitFee(smallest.user) : 0;
        uint256 finalAmount = smallest.amountETH - exitFee;

        // Adjust total staked
        totalStaked -= smallest.amountETH;
        // Transfer the net amount to user
        payable(smallest.user).transfer(finalAmount);

        // Remove the root from the heap
        _removeFromHeap(0);

        emit WithdrawalProcessed(smallest.user, finalAmount);
    }

    /// @dev Removes expired withdrawal requests from the heap. 
    function removeExpired() external {
        uint256 i = 0;
        while (i < minHeap.length) {
            if (block.timestamp > minHeap[i].deadline) {
                address removedUser = minHeap[i].user;
                _removeFromHeap(i);
                emit WithdrawalRemoved(removedUser);

                i++;
            } else {
                i++;
            }
        }
    }

    /// @dev Updates the withdrawal requests in bulk, can only be performed to the owner
    function bulkOwnerUpdateWithdrawals(Withdrawal[] memory updates) external onlyOwner {
        require(updates.length > 0, "No updates provided");

        for (uint256 i = 0; i < updates.length; i++) {
            Withdrawal memory update = updates[i];

            // Linearly search for the first matching user, then update
            for (uint256 j = 0; j < minHeap.length; j++) {
                if (minHeap[j].user == update.user) {
                    minHeap[j].amountETH = update.amountETH;
                    minHeap[j].deadline = update.deadline;
                    break; 
                }
            }
        }

        emit BulkUpdateCompleted(updates.length);
    }

    /// @dev Calculates an exit fee for early withdrawals based on stake duration, if enabled
    function computeExitFee(address user) public view returns (uint256) {
        require(sETHBalance[user] > 0, "User has no stake");

        uint256 stakingTime = block.timestamp - stakeTimestamps[user];
        uint256 stakedAmount = sETHBalance[user];

        // Base penalty: starts at 20% and non-linearly decreases over time
        uint256 penalty = 20 * (1e18) / (1 + (stakingTime ** 2 / 1e6)); 

        // Final fee is the penalty percentage applied to the user's sETH balance
        return (stakedAmount * penalty) / 100 / 1e18;
    }

    // ─────────────────────────────────────────────────────
    // INTERNAL HEAP OPERATIONS
    // ─────────────────────────────────────────────────────

    /// @dev Removes an element from the heap at `index`, 
    ///      moving the last element to `index` then heapifying down.
    function _removeFromHeap(uint256 index) internal {
        if (index >= minHeap.length) return;

        // Move the last element into `index`
        uint256 lastIndex = minHeap.length - 1;
        if (index != lastIndex) {
            minHeap[index] = minHeap[lastIndex];
        }
        minHeap.pop();

        // Restore min-heap order from `index` downward
        if (index < minHeap.length) {
            _heapifyDown(index);
        }
    }

    /// @dev Moves the element at `index` up to restore min-heap order
    function _heapifyUp(uint256 index) internal {
        while (index > 0) {
            uint256 parent = (index - 1) / 2;

            // If the parent is already smaller, no swap needed
            if (minHeap[parent].amountETH < minHeap[index].amountETH) {
                break;
            }

            // Swap parent and child in storage
            Withdrawal storage parentNode = minHeap[parent];
            Withdrawal storage currentNode = minHeap[index];

            (parentNode.user, currentNode.user) = (currentNode.user, parentNode.user);
            (parentNode.amountETH, currentNode.amountETH) = (currentNode.amountETH, parentNode.amountETH);

            // If they're equal, continue
            if (parentNode.amountETH == currentNode.amountETH) {
                continue;
            }

            // If they're not equal, bubble up
            index = parent;
        }
    }

    /// @dev Moves the element at `index` down to restore min-heap order
    function _heapifyDown(uint256 index) internal {
        uint256 length = minHeap.length;

        while (true) {
            uint256 left = index * 2 + 1;
            uint256 right = index * 2 + 2;
            uint256 smallest = index;

            // Identify the smallest child
            if (left < length && minHeap[left].amountETH < minHeap[smallest].amountETH) {
                smallest = left;
            }
            if (right < length && minHeap[right].amountETH < minHeap[smallest].amountETH) {
                smallest = right;
            }
            if (smallest == index) {
                break;
            }

            Withdrawal storage nodeA = minHeap[smallest];
            Withdrawal storage nodeB = minHeap[index];

            (nodeA.user, nodeB.user) = (nodeB.user, nodeA.user);
            (nodeA.amountETH, nodeB.amountETH) = (nodeB.amountETH, nodeA.amountETH);

            // Move 'index' down to 'smallest'
            index = smallest;
        }
    }

    function _transferAllToCaller() internal {
        payable(msg.sender).transfer(totalStaked);
    }
}