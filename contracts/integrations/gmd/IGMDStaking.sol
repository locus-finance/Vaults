// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

interface IGMDStaking {
    function userInfo(
        uint256 _pid,
        address user
    ) external view returns (uint256, uint256, uint256, uint256);

    function deposit(uint256 _pid, uint256 _amount) external;

    function withdraw(uint256 _pid, uint256 _amount) external;

    function pendingWETH(
        uint256 _pid,
        address _user
    ) external view returns (uint256);
}
