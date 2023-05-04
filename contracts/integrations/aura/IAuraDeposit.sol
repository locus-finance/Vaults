// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

interface IAuraDeposit {
    function isShutdown() external view returns (bool);

    function balanceOf(address _account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function poolInfo(
        uint256
    ) external view returns (address, address, address, address, address, bool);

    function rewardClaimed(uint256, address, uint256) external;

    function withdrawTo(uint256, uint256, address) external returns (bool);

    function claimRewards(uint256, address) external returns (bool);

    function rewardArbitrator() external returns (address);

    function setGaugeRedirect(uint256 _pid) external returns (bool);

    function owner() external returns (address);

    function deposit(
        uint256 _pid,
        uint256 _amount,
        bool _stake
    ) external returns (bool);
}
