// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IStakingRewards {
    function stake(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward() external;
    function earned(address account) external view returns(uint256);
    function balanceOf(address account) external view returns(uint256);
}