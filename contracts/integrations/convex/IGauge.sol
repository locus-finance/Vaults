// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IGauge {
    function balanceOf(address staker) external view returns(uint256);
}
