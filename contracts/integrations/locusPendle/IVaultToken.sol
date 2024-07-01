// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IVaultToken is IERC20 {
    function mint(address to, uint256 amount) external;
    function burn(address to, uint256 amount) external;
    function totalSupplyInjected() external view returns (uint256);
    function decreaseSupplyOfOldTokens(uint256 amountToDecrease) external;
    function decimals() external view returns(uint8);
}