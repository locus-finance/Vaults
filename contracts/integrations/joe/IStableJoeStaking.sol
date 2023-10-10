// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IStableJoeStaking {
    function deposit(uint256 _amount) external;

    function getUserInfo(
        address _user,
        address _rewardToken
    ) external view returns (uint256, uint256);

    function pendingReward(
        address _user,
        address _token
    ) external view returns (uint256);

    function withdraw(uint256 _amount) external;

    function feeCollector() external view returns (address);

    function updateReward(address token) external;
}
