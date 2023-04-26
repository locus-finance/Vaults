// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./ICamelotRouter.sol";
import "./INFTPool.sol";

interface IPositionHelper {
    function addLiquidityAndCreatePosition(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 deadline,
        address to,
        INFTPool nftPool,
        uint256 lockDuration
    ) external;

    function addLiquidityETHAndCreatePosition(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        uint256 deadline,
        address to,
        INFTPool nftPool,
        uint256 lockDuration
    ) external payable;
}
