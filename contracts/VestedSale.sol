// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract VestedSale is Ownable {
    struct Vest {
        uint256 vestId;
        uint256 released;
        uint256 tokenAmount;
        bool active;
    }

    address payable presaleReceiver;
    uint256 public minPurchaseTokens;
    uint256 public maxPurchaseTokens;
    uint256 public tokenPerEth;
    uint256 public tokenAllocation;
    uint256 tokensAllocated;
    uint256 public duration;
    IERC20 token;
    bool public enforceWhitelist = true;

    uint256 public start;

    mapping (address => Vest) public vests;
    mapping (address => bool) public whitelist;

    constructor(
        address _token,
        address _receiver,
        uint256 _minPurchaseTokens,
        uint256 _maxPurchaseTokens,
        uint256 _tokenPerEth,
        uint256 _tokenAllocation,
        uint256 _start,
        uint256 _duration
    ) {
        token = IERC20(_token);
        minPurchaseTokens = _minPurchaseTokens;
        maxPurchaseTokens = _maxPurchaseTokens;
        presaleReceiver = payable(_receiver);
        tokenPerEth = _tokenPerEth;
        tokenAllocation = _tokenAllocation;
        start = _start;
        duration = _duration;
    }

    // Fallback function to accept ETH payments
    receive() external payable {}

    // Check if an address is whitelisted
    function isWhitelist(address _address) external view returns(bool) {
        return whitelist[_address];
    }

    // Set whether to enforce whitelist
    function setEnforceWhitelist(bool _enforceWhitelist) external onlyOwner {
        enforceWhitelist = _enforceWhitelist;
    }

    // Set the vesting start time
    function setVestingStartTime(uint256 _start) external onlyOwner {
        require(start > block.timestamp, "Vesting has already started");
        require(_start > block.timestamp, "Start must be in the future");
        start = _start;
    }

    // Add addresses to the whitelist
    function addWhitelist(address[] calldata addresses) external onlyOwner {
        for (uint256 index = 0; index < addresses.length; index++) {
            address _address = addresses[index];
            require(!whitelist[_address], "Address is already whitelisted");
            whitelist[_address] = true;
        }
    }

    // Remove an address from the whitelist
    function removeWhitelist(address _address) external onlyOwner {
        require(whitelist[_address], "Address is not whitelisted");
        whitelist[_address] = false;
    }

    // Buy tokens with ETH
    function buyTokens() external payable {
        uint256 amount = msg.value;
        if (enforceWhitelist) {
            require(whitelist[msg.sender], "Sender is not whitelisted");
        }

        uint256 tokensToAllocate = amount * tokenPerEth / 1 ether;
        tokensAllocated += tokensToAllocate;

        // enusre total allocation not exceeded
        require(tokensAllocated <= tokenAllocation, "Exceeds total allocation");

        Vest storage vest = vests[msg.sender];

        // update the vest
        if (vest.active) {
            vest.tokenAmount += tokensToAllocate;
            require(vest.tokenAmount <= maxPurchaseTokens, "Exceeds max purchase");
            require(vest.tokenAmount >= minPurchaseTokens, "Below min purchase");
        } else {
            require(tokensToAllocate <= maxPurchaseTokens, "Exceeds max purchase");
            require(tokensToAllocate >= minPurchaseTokens, "Below min purchase");
            // Create vest entry
            createVest(msg.sender, tokensToAllocate);
        }

        // Transfer ETH to presaleReceiver
        presaleReceiver.transfer(amount);
    }

    // Internal function to create a new vest entry
    function createVest(address beneficiary, uint256 tokenAmount) internal {
        Vest storage newVest = vests[beneficiary];
        newVest.active = true;
        newVest.tokenAmount = tokenAmount;
    }

    // Release vested tokens to the sender
    function releaseTokens() external {
        Vest storage vest = vests[msg.sender];
        require(vest.active, "Sender has no active vest");
        uint256 releasable = vestedAmount(vest.tokenAmount) - vest.released;
        require(releasable > 0, "No tokens available for release");
        vest.released += releasable;
        token.transfer(msg.sender, releasable);
    }

    // Remove unallocated tokens after vesting
    function removeUnallocatedTokens() external onlyOwner {
        require(start > 0, "Only callable after vesting has started");
        uint256 unallocated = tokenAllocation - tokensAllocated;
        token.transfer(msg.sender, unallocated);
    }

    // Get vesting information for an address
    function vestingInfoByAddress(address _address) public view returns (Vest memory vest, uint256 vested) {
        vest = vests[_address];
        vested = vestedAmount(vest.tokenAmount);
    }

    function vestedAmount(uint256 tokenAmount) public view returns (uint256) {
        if (start >= block.timestamp) {
            return 0;
        } else if (block.timestamp >= start + duration) {
            return tokenAmount;
        } else {
            return tokenAmount * (block.timestamp - start) / duration;
        }
    }

    // Get the time remaining for vesting to complete
    function timeRemaining() external view returns (uint256) {
        return start + duration - block.timestamp;
    }
}
