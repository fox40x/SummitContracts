// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./SafeMath.sol";
import "./SafeMathUint.sol";
import "./SafeMathInt.sol";


interface ISummit is IERC20 {
    function swapEthForTokens(uint256 minTokens, address _address) external payable;
}

contract Oxygen is ERC20, Ownable {
    using SafeMath for uint256;
    using SafeMathUint for uint256;
    using SafeMathInt for int256;
  
    uint256 constant internal magnitude = 2**128;
    uint256 internal magnifiedEthPer02;
    mapping(address => int256) internal magnifiedEthCorrections;
    mapping(address => uint256) internal withdrawnEth;
    uint256 public totalEthDistributed;
    
    ISummit summit;
    IUniswapV2Pair public summitPair;
    IUniswapV2Router02 public uniswapV2Router;

    mapping(address => bool) public excludedFromEth;

    uint256 gameStart;
    uint256 expeditionFrequency = 1 days;

    constructor(address _summit, address _summitPair, address _router) ERC20("Oxygen", "02") {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_router);
        uniswapV2Router = _uniswapV2Router;
        summit = ISummit(_summit);
        summitPair = IUniswapV2Pair(_summitPair);

        excludedFromEth[address(this)] = true;
        excludedFromEth[address(0)] = true;
        excludedFromEth[_summit] = true;
        excludedFromEth[_summitPair] = true;
        excludedFromEth[_router] = true;
    }

    function decimals() public view virtual override returns (uint8) {
        return 9;
    }

    receive() external payable {
        distributeEth(msg.value);
    }

    /// @notice Sets the start time of the game
    /// @param _gameStart The start time
    function setGameStartTime(uint256 _gameStart) external {
        require(msg.sender == address(summit), "Only callable by summit");
        gameStart = _gameStart;
    }
    
    /// @notice Exclude an address from receiving Eth
    /// @param account The address to exclude
    function excludeFromEth(address account) external onlyOwner {
        require(!excludedFromEth[account], "Account is already excluded from Eth");
        uint256 balance = balanceOf(account);

        if (balance > 0) {
            burn02(account, balance);
        }

        uint256 withdrawable = withdrawableEthOf(account);
        if (withdrawable > 0) {
            withdrawnEth[account] += withdrawable;
            distributeEth(withdrawable);
        }
        excludedFromEth[account] = true;
    }
    
    /// @notice Token is not transferrable
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(false, "02 is not transferrable");
    }

    /// @notice Mints tokens to a user when they buy from the summit
    /// @dev Only callable by the summit contract
    /// @dev 
    function onSummitBuy(uint256 tokenAmount, address account) external returns(uint256 generated02) {
        uint256 altitude = getAltitude();
        require(msg.sender == address(summit), "Only callable by summit");
        if (excludedFromEth[account]) {
            return 0;
        }
        generated02 = calculate02(tokenAmount) * altitude;
        _mint(account, generated02);
        mint02(account, generated02);
        return generated02;
    }

    /// @notice Burns tokens when a user sells or transfers their summit tokens
    /// @dev Only callable by the summit contract
    /// @dev Burns the same percentage of 02 as the user is selling of summit
    /// @param tokenAmount The amount of summit being transferred or sold
    /// @param account The address of the user transferring
    function onSummitTransfer(uint256 tokenAmount, address account) external {
        require(msg.sender == address(summit), "Only callable by summit");
        uint256 oxygenBalance = balanceOf(account);
        if (oxygenBalance > 0) {
            uint256 summitBalance = summit.balanceOf(account);
		    uint256 percentage = tokenAmount * 100 / summitBalance;
		    uint256 sacrificed02 = balanceOf(account) * percentage / 100;
            _burn(account, sacrificed02);
            burn02(account, sacrificed02);
        }
    }
    
    /// @notice Calculate the amount of 02 to mint when a user buys summit
    /// @dev Calculates the amount of eth required to buy the tokenAmount of summit
    /// @dev Calculates the price of summit after the purchase
    /// @dev Returns price * token price
    /// @param tokenAmount The amount of summit being bought
    function calculate02(uint256 tokenAmount) public view returns (uint256) {
        (uint256 reserve0, uint256 reserve1,) = summitPair.getReserves();
		(uint256 tokenReserve, uint256 ethReserve) = address(summit) < address(uniswapV2Router.WETH()) ? (reserve0, reserve1) : (reserve1, reserve0);
        uint256 ethInput = uniswapV2Router.getAmountIn(tokenAmount, ethReserve, tokenReserve);
        uint256 tokenPrice = (ethReserve + ethInput) * magnitude / (tokenReserve - tokenAmount);
        // uint256 factor = tokenPrice * tokenPrice / magnitude;
        return ethInput * tokenPrice / magnitude;
    }

    /// @notice Mint 02 tokens to a user
    /// @param account The address of the user to mint to
    /// @param amount The amount of 02 to mint
    function mint02(address account, uint256 amount) internal {
        magnifiedEthCorrections[account] = magnifiedEthCorrections[account]
        .sub( (magnifiedEthPer02.mul(amount)).toInt256Safe() );
      }

    /// @notice Burn 02 tokens from a user
    /// @param account The address of the user to burn from
    /// @param amount The amount of 02 to burn
    function burn02(address account, uint256 amount) internal {
        magnifiedEthCorrections[account] = magnifiedEthCorrections[account]
        .add((magnifiedEthPer02.mul(amount)).toInt256Safe() );
      }

    /// @notice Distribute eth to all holders
    /// @param amount The amount of eth to distribute
    function distributeEth(uint256 amount) internal {
        require(totalSupply() > 0);
        if (msg.value > 0) {
            magnifiedEthPer02 = magnifiedEthPer02.add(
              (amount).mul(magnitude) / totalSupply()
            );
      
            totalEthDistributed = totalEthDistributed.add(msg.value);
          }
          }
    
    /// @notice Withdraw eth from the contract
    function withdrawEth() external {
        _withdrawEth(msg.sender);
    }

    /// @notice Withdraw eth from the contract
    /// @param account The address to withdraw from
    function _withdrawEth(address account) internal {
        uint256 _withdrawableDividend = withdrawableEthOf(account);
        if (_withdrawableDividend > 0) {
          withdrawnEth[account] = withdrawnEth[account].add(_withdrawableDividend);
          (bool success,) = account.call{value: _withdrawableDividend}("");
    
          if(!success) {
            withdrawnEth[account] = withdrawnEth[account].sub(_withdrawableDividend);
          }
        }
        }

    /// @notice Get the amount of eth a user can withdraw
    /// @param account The address to check
    function withdrawableEthOf(address account) public view returns(uint256) {
        return excludedFromEth[account] ? 0 : accumulativeEthOf(account).sub(withdrawnEth[account]);
    }
    
    /// @notice Get the amount of eth a user has withdrawn
    /// @param account The address to check
    function withdrawnEthOf(address account) public view returns(uint256) {
        return withdrawnEth[account];
    }
    
    /// @notice Get the amount of eth a user has accumulated
    /// @param account The address to check
    function accumulativeEthOf(address account) public view returns(uint256) {
        return magnifiedEthPer02.mul(balanceOf(account)).toInt256Safe()
        .add(magnifiedEthCorrections[account]).toUint256Safe() / magnitude;
      }

    /// @notice Get the current altitude
    /// @dev Altitude is the number of expeditions completed
    function getAltitude() public view returns (uint256) {
        return (block.timestamp - gameStart) / expeditionFrequency + 1;
    }

    /// @notice Get the timestamp of the next expedition
    function getNextExpedition() public view returns (uint256) {
        return block.timestamp - gameStart - (expeditionFrequency * ((block.timestamp - gameStart) / expeditionFrequency));
    }

    /// @notice Get the state of a user
    /// @param _address The address to check
    function gameState(address _address) external view returns (
        uint256 altitude,
        uint256 nextExpedition,
        uint256 oxygenBalance,
        uint256 summitBalance,
        uint256 withdrawable,
        uint256 withdrawn
    ) {
        altitude = getAltitude();
        nextExpedition = getNextExpedition();
        oxygenBalance = balanceOf(_address);
        withdrawable = withdrawableEthOf(_address);
        withdrawn = withdrawnEthOf(_address);
        summitBalance = summit.balanceOf(_address);
    }

    /// @notice User can keep climbing
    /// @dev User can withdraw eth and swap for summit without incurring a fee on purchase
    /// @param minTokens The minimum amount of summit to receive
    function keepClimbing(uint256 minTokens) external {
        uint256 withdrawable = withdrawableEthOf(msg.sender);
        if (withdrawable > 0) {
            withdrawnEth[msg.sender] += withdrawable;
            summit.swapEthForTokens{value: withdrawable}(minTokens, msg.sender);
        }
    }
}
