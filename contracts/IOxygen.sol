pragma solidity ^0.8.4;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IOxygen is IERC20 {
    function onSummitBuy(uint256 tokenAmount, address account) external returns(uint256 generated02);
    function onSummitTransfer(uint256 tokenAmount, address account) external;
    function setGameStartTime(uint256 _gameStart) external;
}