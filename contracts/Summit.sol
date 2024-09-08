// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;
import "./IOxygen.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

/// @title Summit
/// @author FOX40X
/// @notice Summit is on on chain experimental game where users can buy and sell tokens to participate
/// @dev A fee is taken on each buy and sell to fund the contractor, climber awareness fund and community
/// The game starts at a set time and users can buy and sell tokens to participate
/// The distribution of funds is controlled by the oxygen contract
/// The higher a user's balance of oxygen the more eth they will receive when the ethereum is distributed

contract Summit is ERC20, Ownable {
    IUniswapV2Router02 public uniswapV2Router;
    IUniswapV2Pair public uniswapV2Pair;
    IOxygen public oxygen;

    uint256 contractorGratuity = 2;
    uint256 climberAwarenessFund = 1;
    uint256 communityContribution = 9;
    uint256 totalContribution = 12;

    address payable contractorAddress = payable(0x1f4b51737FDa4231Ca06C195b6Cc64f862D10E13);
    address payable climberAwarenessAddress = payable(0x2082059A610E8A82DD19EFfdfAF7601048c3095f);

    mapping(address => bool) public excludedFromFee;
    bool swapping;
    uint256 swapThreshold = 5000000 ether;

    uint256 gameStart = 99672491600;

    constructor(
        address _uniswapRouterAddress
    ) ERC20("Summit", "SUMMIT") {    
    	IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_uniswapRouterAddress);
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = IUniswapV2Pair(_uniswapV2Pair);

        excludedFromFee[address(this)] = true;
        excludedFromFee[msg.sender] = true;
        _mint(msg.sender, 1_000_000_000 * (10**18));
    }

    receive() external payable {}

    /// @notice Sets the start time of the game
    function setGameStartTime(uint256 _gameStart) external onlyOwner {
        require(gameStart > block.timestamp, "Game has already started");
        require(_gameStart > block.timestamp, "Start must be in the future");
        oxygen.setGameStartTime(_gameStart);
        gameStart = _gameStart;
    }

    /// @notice Set an address to be excluded from fees
    /// @param _address The address to exclude
    /// @param value Whether to exclude the address
    function setExcluded(address _address, bool value) external onlyOwner {
        excludedFromFee[_address] = value;
    }
    
    /// @notice Sets the oxygen contract address
    /// @param _address The address of the oxygen contract
    function setOxygen(address payable _address) external onlyOwner {
        oxygen = IOxygen(_address);
        excludedFromFee[address(_address)] = true;
    }

    /// @notice Sets the contractor address
    /// @param _address The address of the contractor
    function setContractorAddress(address payable _address) external onlyOwner {
        contractorAddress = _address;
    }

    /// @notice Sets the climber awareness address
    /// @param _address The address of the climber awareness fund
    function setClimberAwarenessAddress(address payable _address) external onlyOwner {
        climberAwarenessAddress = _address;
    }

    /// @notice Overides the transfer function to implement fees and game logic
    /// @dev Takes a fee if required
    /// @dev Ensures the game has started
    /// @dev Calls the oxygen contract to update the game state
    /// @dev Swaps tokens for eth if the balance is above the threshold
    /// @param from The address to transfer from
    /// @param to The address to transfer to
    /// @param amount The amount to transfer
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        bool excluded = excludedFromFee[from] || excludedFromFee[to] || swapping;
        if (!excluded) {
            require(gameStart < block.timestamp, "The game has not started");
        }
        if (from == address(uniswapV2Pair)) {
            oxygen.onSummitBuy(amount, to);
        } else {
            oxygen.onSummitTransfer(amount, from);
            if (!excluded && balanceOf(address(this)) > swapThreshold) {
                swapAndDistribute(swapThreshold);
            }
        }

        if (!excluded) {
            // take a fee on all transfers
        	uint256 fees = amount * totalContribution / 100;
            super._transfer(from, address(this), fees);
            super._transfer(from, to, amount - fees);
        } else {
            super._transfer(from, to, amount);
        }
    }

    /// @notice Manually swap and distribute if tokens become stuck at router
    /// @param tokenAmount The amount of tokens to swap and distribute
    function emergencySwapAndDistribute(uint256 tokenAmount) external onlyOwner {
        swapAndDistribute(tokenAmount);
    }

    /// @notice Swaps tokens for eth and distributes the eth to the contractor, climber awareness fund and community
    /// @param tokenAmount The amount of tokens to swap
    function swapAndDistribute(uint256 tokenAmount) internal {
        swapTokensForEth(tokenAmount);
        distribute();
    }

    /// @notice Swaps tokens held in the contract for Ethereum
    /// @param tokenAmount The amount of tokens to swap
    function swapTokensForEth(uint256 tokenAmount) internal {
        swapping = true;
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
        swapping = false;
    }

    /// @notice Swaps Ethereum for tokens
    /// @dev Only callable by the oxygen contract
    /// @dev Allows a user to bypass the fee when using their accrued eth to buy tokens
    /// @param minTokens The minimum amount of tokens to receive
    /// @param _address The address to send the tokens to
    function swapEthForTokens(uint256 minTokens, address _address) external payable {
        require(msg.sender == address(oxygen), "Only callable by oxygen");
        _swapEthForTokens(msg.value, minTokens, _address);
    }

    /// @notice Call uniswap to swap eth for tokens
    /// @param ethAmount The amount of eth to swap
    /// @param minTokens The minimum amount of tokens to receive
    /// @param _address The address to send the tokens to
    function _swapEthForTokens(uint256 ethAmount, uint256 minTokens, address _address) internal {
        swapping = true;
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = address(this);
        uniswapV2Router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: ethAmount}(minTokens, path, _address, block.timestamp);
        swapping = false;
    }

    /// @notice Distributes the eth held in the contract to the contractor, climber awareness fund and community
    function distribute() public {
        uint256 ethBalance = address(this).balance;
        uint256 contractor = ethBalance * contractorGratuity / totalContribution;
        uint256 climber = ethBalance * climberAwarenessFund / totalContribution;
        uint256 community = ethBalance - contractor - climber;

        contractorAddress.transfer(contractor);
        climberAwarenessAddress.transfer(climber);
        (bool success, ) = address(oxygen).call{value: community}("");
        require(success, "Distibute failed");
    }
}
